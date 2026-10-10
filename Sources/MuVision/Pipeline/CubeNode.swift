//  created by musesum on 3/16/23.

import UIKit
import Metal
import CoreImage
import simd
import ModelIO
import MetalKit
#if os(visionOS)
import CompositorServices
#endif
import MuFlo

public struct VertexCube {
    var position : vector_float4 = .zero
}

public class CubeNode: RenderNode, @unchecked Sendable {

    internal let viaIndex   : Bool
    internal var cubeMesh   : CubeMesh!
    internal var cubeIndex  : CubemapIndex?
    internal var inTex˚     : Flo?
    internal var cudex˚     : Flo?
    internal var mixcube˚   : Flo?
    internal var lastAspect : Aspect?
    internal var lastSize   : CGSize?  // pipe size the index cube was made at
    internal var zoom˚      : Flo?
    internal var zoom       : Float = 0

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        self.cubeMesh = CubeMesh(pipeline.renderState)
        self.viaIndex = true
        super.init(pipeline, pipeFlo˚)
        pipeline.resizeNodes.append { [weak self] in self?.makeCube() }

        inTex˚    = pipeFlo˚.superBindPath("in")
        cudex˚    = pipeFlo˚.superBindPath("cudex")
        mixcube˚  = pipeFlo˚.superBindPath("mixcube")
        zoom˚     = pipeFlo˚.getRoot().bind("plato.phase") { f,_ in
            self.zoom = Float((f.exprs?.nameAny["zoom"] as? Scalar)?.tween ?? 0)
        }
        frustum˚  = pipeFlo˚.getRoot().bind("pipe.render.frustum") { f,_ in
            self.frustum = f.float
        }
        frustum = frustum˚?.float ?? 0
        // plato.cubemap and plato.cube turn the view the cube and plato share
        CubeNav.shared.bind(pipeFlo˚.getRoot())
    }
    private var frustum˚: Flo?
    private var frustum = Float(0)
    
    override public func makeShader() {
        shader = Shader(pipeline, "render.map.cube",
                        vertex: "cubeVertex",
                        fragment: "cubeIndexFragment")
        renderPipelineState = makeRenderState(cubeMesh.mtlVD)
    }

    override open func makeResources() {
        
        self.makeCube()
        self.cubeMesh.eyeBuf = EyeBuf("CubeEyes", self.pipeline, far: false)
    }

    override open func renderShader(
        _ encoder: MTLRenderCommandEncoder,
        _ state: RenderState) {

            guard cudex˚?.texture ?? nil != nil else { return }
            guard let renderPipelineState else { return }

            cubeMesh.eyeBuf?.setUniformBuf(encoder)
            if let mixcube˚ {
            #if os(visionOS)
            mixcube˚.setNameNums([("x", 1)], .fire) //....
            #endif
            mixcube˚.updateMtlBuffer()
        }
        encoder.setFragmentTexture(inTex˚,   index: 0)
        encoder.setFragmentTexture(cudex˚,   index: 1)
        encoder.setFragmentBuffer (mixcube˚, index: 0)

        encoder.setRenderPipelineState(renderPipelineState)
        cubeMesh.drawMesh(encoder, state)
        cudex˚?.reactivate()
    }

    // for both metal and visionOS reflection
    override public func updateUniforms() {
        guard let eyebuf = cubeMesh.eyeBuf else { return }

        Task {
            let orientation = await Motion.shared.updateDeviceOrientation()
            let nav = CubeNav.shared
            eyebuf.updateMetalEyeUniforms(nav.view(orientation), frustum: frustum, zoom: nav.zoom)
        }
    }
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {

        let inAdr = inTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr))"
        super.logShader(&logging, inOut)
    }

    /// drawable pixel → the texture fraction the cubemap shows there: the
    /// sight ray through the last cube projection, sampled as the fragment
    /// does (x, y, -z) through the index cube; nil while the cube is mixed
    /// out or before its first frame
    /// mixcube.x as the fragment reads it: the uniform buffer, not the flo
    var mixShown: Float {
        guard let buf = mixcube˚?.buffer else { return 0 }
        return buf.contents().bindMemory(to: Float.self, capacity: 2)[0]
    }
    public func textureFraction(_ point: SIMD2<Float>) -> SIMD2<Float>? {
        guard pipeFlo˚.val("on") ?? 0 > 0,
              mixShown > 0.5,
              let cubeIndex, let eyeBuf = cubeMesh.eyeBuf else { return nil }
        let size = pipeline.layer.drawableSize
        guard size.width > 0, size.height > 0 else { return nil }
        let nx = point.x / Float(size.width) * 2 - 1
        let ny = 1 - point.y / Float(size.height) * 2
        let v = eyeBuf.projection.inverse * SIMD4<Float>(nx, ny, 0.5, 1)
        guard abs(v.w) > 1e-9 else { return nil }
        let view = SIMD4<Float>(v.x / v.w, v.y / v.w, v.z / v.w, 0) // eye at the origin
        let m = (eyeBuf.viewModel.inverse * view).xyz
        let r = SIMD3<Float>(m.x, m.y, -m.z)
        let ax = abs(r.x), ay = abs(r.y), az = abs(r.z)
        let quad: Quad
        let sc: Float, tc: Float, ma: Float
        if ax >= ay, ax >= az {
            ma = ax
            if r.x > 0 { quad = cubeIndex.left;  sc = -r.z; tc = -r.y }
            else       { quad = cubeIndex.right; sc =  r.z; tc = -r.y }
        } else if ay >= az {
            ma = ay
            if r.y > 0 { quad = cubeIndex.top; sc = r.x; tc =  r.z }
            else       { quad = cubeIndex.bot; sc = r.x; tc = -r.z }
        } else {
            ma = az
            if r.z > 0 { quad = cubeIndex.front; sc =  r.x; tc = -r.y }
            else       { quad = cubeIndex.back;  sc = -r.x; tc = -r.y }
        }
        guard ma > 1e-9 else { return nil }
        let side = cubeIndex.side
        let s = min(side - 1, max(0, Int((sc / ma + 1) * 0.5 * Float(side))))
        let t = min(side - 1, max(0, Int((tc / ma + 1) * 0.5 * Float(side))))
        let uv = quad[t * side + s]
        guard uv.0 >= 0 else { return nil }
        return SIMD2<Float>(Float(uv.0), Float(uv.1))
    }
#if os(visionOS)

    /// Update projection and rotation
    override public func updateUniforms(_ drawable : LayerRenderer.Drawable,
                                        _ anchor   : DeviceAnchor?) {
        cubeMesh.eyeBuf?.updateVisionEyeUniforms(drawable, anchor, zoom, "👁️C⃝ube")
    }

#endif

}
