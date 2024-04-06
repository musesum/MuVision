// created by musesum

import MetalKit
import Spatial
import simd
#if os(visionOS)
import CompositorServices
#endif
import MuFlo

/// triple buffered Uniform for either 1 or 2 eyes
open class UniformEyeBuf {

    public struct UniEyes {
        var eye: (UniformEye, UniformEye) // a uniform for each eye
    }
    let uniformSize: Int
    let tripleUniformSize: Int
    let uniformBuf: MTLBuffer
    let infinitelyFar: Bool // infinit distance for stars (same background for both eyes)

    var uniformEyes: UnsafeMutablePointer<UniEyes>!
    var tripleOffset = 0
    var tripleIndex = 0
    var rotation: Float = 0

    public init(_ device: MTLDevice,
                _ label: String,
                far: Bool) {

        // round up to multiple of 256 bytes
        self.uniformSize = (MemoryLayout<UniEyes>.size + 0xFF) & -0x100
        self.tripleUniformSize = uniformSize * TripleBufferCount
        self.infinitelyFar = far
        self.uniformBuf = device.makeBuffer(length: tripleUniformSize, options: [.storageModeShared])!
        self.uniformBuf.label = label

        nextTripleUniformBuffer()
    }
#if os(visionOS)

    /// Update projection and rotation
    public func updateEyeUniforms(_ layerDrawable: LayerRenderer.Drawable,
                                  _ cameraPos: vector_float4,
                                  _ label: String) {

        nextTripleUniformBuffer()

        let deviceAnchor = WorldTracking.shared.deviceAnchor
        let anchorOrigin = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        uniformEyes[0].eye.0 = uniformForEyeIndex(0, label)
        if layerDrawable.views.count > 1 {
            uniformEyes[0].eye.1 = uniformForEyeIndex(1)
        }

        MuLog.Log(label, interval: 4) {
            let tab = "\t\(label[0...1])"

            if layerDrawable.views.count > 1 {
                let view0 = layerDrawable.views[0]
                let view1 = layerDrawable.views[1]
                let orient0 =  (anchorOrigin * view0.transform).inverse
                let orient1 =  (anchorOrigin * view1.transform).inverse

                let eye0 = self.uniformEyes[0].eye.0
                let eye1 = self.uniformEyes[0].eye.1
                print(tab+" projection  0:\(eye0.projection.script(-2))")
                print(tab+"             1:\(eye1.projection.script(-2))")
                print(tab+" orientation 0:\(orient0.script)")
                print(tab+"             1:\(orient1.script)")
                print("\t👁️ viewModel   ", "0:\(eye0.viewModel.script(-2))")
            } else {
                let view0 = layerDrawable.views[0]
                let orient0 =  (anchorOrigin * view0.transform).inverse

                let eye0 = self.uniformEyes[0].eye.0
                print(tab+" projection  0:\(eye0.projection.script)")
                print(tab+" orientation 0:\(orient0.script)")
                print(tab+" viewModel   0:\(eye0.viewModel.script)")
            }
            func tangentsDepthStr(_ index: Int) -> String {
                let view = layerDrawable.views[index]
                return "\(view.tangents.script(-2)); \(layerDrawable.depthRange.script(-2))"
            }
        }

        func uniformForEyeIndex(_ index: Int, 
                                _ label: String? = nil) -> UniformEye {

            let view = layerDrawable.views[index]
            let projection = ProjectiveTransform3D(
                leftTangent   : Double(view.tangents[0]),
                rightTangent  : Double(view.tangents[1]),
                topTangent    : Double(view.tangents[2]),
                bottomTangent : Double(view.tangents[3]),
                nearZ         : Double(layerDrawable.depthRange.y),
                farZ          : Double(layerDrawable.depthRange.x),
                reverseZ      : true)

            let orientation = (anchorOrigin * view.transform).inverse
            var viewModel = orientation

            if infinitelyFar {
                viewModel = orientation
                viewModel.columns.3 = simd_make_float4(0, 0, 0, 1)
            } else {
                viewModel *= updateRotation() //?????
            }
            let uniformEye = UniformEye(.init(projection), viewModel)

            return uniformEye
        }
        /// rotate model
        func updateRotation() -> matrix_float4x4 {
            //???? rotation += 0.01
            return cameraPos.translate * SIMD3<Float>(1, 1, 0).rotate(radians: rotation)
        }
    }
    #endif
    /// Update projection and rotation
    public func updateEyeUniforms(_ projection: matrix_float4x4,
                                  _ viewModel: matrix_float4x4) {

        nextTripleUniformBuffer()

        self.uniformEyes[0].eye.0 = UniformEye(projection, viewModel)
    }

    func nextTripleUniformBuffer() {

        tripleIndex = (tripleIndex + 1) % TripleBufferCount
        tripleOffset = uniformSize * tripleIndex
        let uniformPtr = uniformBuf.contents() + tripleOffset
        uniformEyes = UnsafeMutableRawPointer(uniformPtr)
            .bindMemory(to: UniEyes.self, capacity: 1)
    }

    public func setUniformBuf(_ renderCmd: MTLRenderCommandEncoder, _ from: String)  {

        renderCmd.setVertexBuffer(uniformBuf,
                                  offset: tripleOffset,
                                  index: 3 /*VertexIndex.uniforms*/)
        //print("\(from): \(tripleOffset)", terminator: " ")
    }

}
