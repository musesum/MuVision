// created by musesum
#if !os(visionOS)
import MetalKit
#else
import CompositorServices
#endif
import Spatial

/// triple buffered Uniform for either 1 or 2 eyes
open class UniformEyeBuf<Item> {

    public struct UniEyes {
        var eye: (Item, Item) // a uniform for each eye
    }

    let uniformSize: Int
    let tripleUniformSize: Int
    let uniformBuf: MTLBuffer
    let infinitelyFar: Bool // infinit distance for stars (same background for both eyes)

    var uniformEyes: UnsafeMutablePointer<UniEyes>!
    var tripleOffset = 0
    var tripleIndex = 0
    
    public init(_ device: MTLDevice,
                _ label: String,
                far: Bool) {

        // round up to multiple of 256 bytes
        self.uniformSize = (MemoryLayout<UniEyes>.size + 0xFF) & -0x100
        self.tripleUniformSize = uniformSize * TripleBufferCount
        self.infinitelyFar = far
        self.uniformBuf = device.makeBuffer(length: tripleUniformSize, options: [.storageModeShared])!
        self.uniformBuf.label = label
        updateTripleBufferedUniform()
    }
#if !os(visionOS)

#else

    /// Update projection and rotation
    public func updateEyeUniforms(_ layerDrawable: LayerRenderer.Drawable,
                                  _ modelMatrix: simd_float4x4) {
        updateTripleBufferedUniform()

        let anchor = (layerDrawable.deviceAnchor?.originFromAnchorTransform
                      ?? matrix_identity_float4x4)

        self.uniformEyes[0].eye.0 = uniformForEyeIndex(0)
        if layerDrawable.views.count > 1 {
            self.uniformEyes[0].eye.1 = uniformForEyeIndex(1)
        }

        func uniformForEyeIndex(_ index: Int) -> Item {

            let view = layerDrawable.views[index]

            let projection = ProjectiveTransform3D(
                leftTangent   : Double(view.tangents[0]),
                rightTangent  : Double(view.tangents[1]),
                topTangent    : Double(view.tangents[2]),
                bottomTangent : Double(view.tangents[3]),
                nearZ         : Double(layerDrawable.depthRange.y),
                farZ          : Double(layerDrawable.depthRange.x),
                reverseZ      : true)

            let viewMatrix = (anchor * view.transform).inverse
            var viewModel = viewMatrix * modelMatrix

            if infinitelyFar {
                viewModel.columns.3 = simd_make_float4(0.0, 0.0, 0.0, 1.0)
            }
            let eyeUniforms = UniformEye(.init(projection), viewModel)
            return eyeUniforms as! Item
        }
    }
#endif
    func updateTripleBufferedUniform() {

        tripleIndex = (tripleIndex + 1) % TripleBufferCount
        tripleOffset = uniformSize * tripleIndex
        let uniformPtr = uniformBuf.contents() + tripleOffset
        uniformEyes = UnsafeMutableRawPointer(uniformPtr)
            .bindMemory(to: UniEyes.self, capacity: 1)
    }

    func setUniformBuf(_ renderCmd: MTLRenderCommandEncoder)  {

        renderCmd.setVertexBuffer(uniformBuf,
                                  offset: tripleOffset,
                                  index: 3 /*VertexIndex.uniforms*/)
    }

}
