// created by musesum

import MetalKit
import MuFlo // project4x4
/// triple buffered Uniform for either 1 or 2 eyes
open class EyeBuf {

    public struct UniEyes {
        var eye: (UniformEye, UniformEye) // a uniform for each eye
    }
    let pipeline: Pipeline
    let eyeSize: Int
    let eye3Size: Int // triple buffer
    let infinitelyFar: Bool // infinit distance for stars (same background for both eyes)
    let eyeBuf: MTLBuffer
    var eyes: UnsafeMutablePointer<UniEyes>!
    var tripleOffset = 0
    var tripleIndex = 0

    public init?(_ label: String,
                 _ pipeline: Pipeline,
                 far: Bool) {
        self.pipeline = pipeline
        // round up to multiple of 256 bytes
        self.eyeSize = (MemoryLayout<UniEyes>.size + 0xFF) & -0x100
        self.eye3Size = eyeSize * 3 // triple buffer
        self.infinitelyFar = far
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.eyeBuf = device.makeBuffer(length: eye3Size, options: [.storageModeShared])!
        self.eyeBuf.label = label
        nextTripleUniformBuffer()
    }

    /// Update projection and rotation for flat surface
    public func updateMetalEyeUniforms(_ viewModel: matrix_float4x4) {
        let projection = project4x4(pipeline.layer.drawableSize)
        nextTripleUniformBuffer()
        self.eyes[0].eye.0 = UniformEye(projection, viewModel)
    }

    /// WinSky near plane: the slider runs the near distance down with the
    /// frame height fixed, so tan half-fov = tan0 / near; near 1 → 0.01
    /// spans the neutral POV to the radial spokes (100× wider). one smooth
    /// curve, no dead zone: nearer than 0.01 squeezes the view to a dot
    static let widenMax: Float = 0.99
    static func widenTan(_ tan0: Float, _ frustum: Float) -> Float {
        tan0 / (1 - widenMax * min(max(frustum, 0), 1))
    }

    /// plato.cube zoom: the neutral field of view narrowed up to 4× at zoom 1;
    /// the eye stays put, so a touch still maps through the stored
    /// projection. zoom 0 is the view as it was
    public static let zoomMax: Float = 4
    static func zoomTan(_ tan: Float, _ zoom: Float) -> Float {
        tan / pow(zoomMax, min(max(zoom, 0), 1))
    }

    /// the cube and plato's place before the viewer on visionOS: `placeFar`
    /// metres ahead at zoom 0, `placeRun` nearer by zoom 1; scale `scaleMin`
    /// + zoom; lifted `placeUp`
    public static let placeFar: Float = 4
    public static let placeRun: Float = 3
    public static let scaleMin: Float = 0.05
    public static let placeUp: Float = 1
    /// full immersion keeps the head this far inside the cube's near wall
    public static let cubeInset: Float = 0.5

    /// zoom's floor: 0 in mixed, where the range ends; in full immersion the
    /// zoom at which the cube, half a side `r` model units, still holds
    /// `head` (world metres) `cubeInset` inside every wall, so its boundary
    /// never passes through the viewer
    public static func zoomFloor(head: SIMD3<Float>, cubeRadius r: Float, full: Bool) -> Float {
        guard full else { return 0 }
        let x = (abs(head.x) + cubeInset) / r - scaleMin
        let y = (abs(head.y - placeUp) + cubeInset) / r - scaleMin
        // near wall −placeFar + placeRun·z + r(scaleMin + z) > head.z + cubeInset
        let z = (head.z + cubeInset + placeFar - r * scaleMin) / (placeRun + r)
        return min(1, max(0, x, y, z))
    }

    /// zoom within `floorBand` of the floor blends toward it by the standard
    /// cubic 3t²−2t³: slope 0 at the floor, 1 at the band's top; below the
    /// floor it holds there
    public static let floorBand: Float = 0.15
    public static func zoomEased(_ zoom: Float, floor: Float) -> Float {
        let t = min(max((zoom - floor) / floorBand, 0), 1)
        return floor + (zoom - floor) * t * t * (3 - 2 * t)
    }

    /// tan half-fov for plato.cube frustum and zoom: zoom narrows
    /// the neutral view, and the frustum widens from there to the radial
    /// spokes -- at frustum 1 the full spokes, 100× the neutral tan, at any
    /// zoom, so the WZ thumb's height never stops frustum 1 short of them.
    /// Zoom's narrowing fades as the frustum opens. At zoom 0 this is
    /// widenTan, the frustum's curve as it always was
    public static func viewTan(_ tan0: Float, frustum: Float, zoom: Float) -> Float {
        let f = min(max(frustum, 0), 1)
        let zoomed = zoomTan(tan0, zoom)
        // 1 − reach = zoomed / (100 tan0): frustum 1 lands on the spokes
        let reach = 1 - (1 - widenMax) * zoomed / tan0
        return zoomed / (1 - reach * f)
    }

    /// field of view widened from the neutral POV (0) toward the radial
    /// spokes (1), and narrowed by `zoom`; near 0.01 keeps the r 10 cube
    /// unclipped out to tan 1000, past the widest landscape spokes (≈ 125)
    public func updateMetalEyeUniforms(_ viewModel: matrix_float4x4,
                                       frustum: Float,
                                       zoom: Float = 0) {
        let size = pipeline.layer.drawableSize
        let aspect = Float(size.width / size.height)
        let fovy0 = Float(aspect >= 1 ? 60.0 : 90.0) / 180 * .pi
        let fovy = 2 * atan(Self.viewTan(tan(fovy0 / 2), frustum: frustum, zoom: zoom))
        let projection = project4x4(size, near: 0.01, fov: fovy / fovy0)
        self.projection = projection
        self.viewModel = viewModel
        nextTripleUniformBuffer()
        self.eyes[0].eye.0 = UniformEye(projection, viewModel)
    }

    public private(set) var projection = matrix_identity_float4x4
    public private(set) var viewModel = matrix_identity_float4x4
    #if os(visionOS)
    /// the last frame's placement, model → world, and the device anchor's
    /// position: a pinch's sight ray in model space (PlatoNode+PressPinch)
    public internal(set) var visionModel = matrix_identity_float4x4
    public internal(set) var visionHead = SIMD3<Float>.zero
    #endif

    /// eye pulled back to `distance` with the field of view narrowed to keep
    /// the apparent size: 0.01 = inside the object, 1000 = the infinite point;
    /// `eyeDistance` = where the eye actually sits after zoom, for near/far
    public func updateMetalEyeUniforms(_ viewModel: matrix_float4x4,
                                       distance: Float,
                                       eyeDistance: Float? = nil,
                                       frustum: Float = 0,
                                       zoom: Float = 0,
                                       baseDistance: Float = 4) {
        let size = pipeline.layer.drawableSize
        let aspect = Float(size.width / size.height)
        let fovy0 = Float(aspect >= 1 ? 60.0 : 90.0) / 180 * .pi
        let fovy = 2 * atan(Self.viewTan(tan(fovy0 / 2) * baseDistance / max(0.01, distance), frustum: frustum, zoom: zoom))
        let eyeZ = eyeDistance ?? distance
        let near = max(0.001, eyeZ - 3)
        let far = max(near + 1, abs(eyeZ) + 3)
        let projection = perspectiveDepth01(aspect, fovy, near, far)
        self.projection = projection
        self.viewModel = viewModel
        nextTripleUniformBuffer()
        self.eyes[0].eye.0 = UniformEye(projection, viewModel)
    }

    /// Metal 0…1 depth: near → 0, far → 1 for any near/far pair
    /// (`perspective4x4` lands in range only when near ≪ far)
    private func perspectiveDepth01(_ aspect: Float,
                                    _ fovy: Float,
                                    _ near: Float,
                                    _ far: Float) -> matrix_float4x4 {
        let yScale = 1 / tan(fovy * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -far / zRange
        let wzScale = -far * near / zRange
        return matrix_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)))
    }

    func nextTripleUniformBuffer() {

        tripleIndex = (tripleIndex + 1) % 3 // triple buffer
        tripleOffset = eyeSize * tripleIndex
        let eyePtr = eyeBuf.contents() + tripleOffset
        eyes = UnsafeMutableRawPointer(eyePtr)
            .bindMemory(to: UniEyes.self, capacity: 1)
    }

    public func setUniformBuf(_ encoder: MTLRenderCommandEncoder)  {
        encoder.setVertexBuffer(eyeBuf, offset: tripleOffset, index: 15)
    }

}
