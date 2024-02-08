// created by musesum

import MetalKit
import Spatial
import simd
#if os(visionOS)
import CompositorServices
#endif
import MuExtensions

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

        updateTripleBufferedUniform()
    }
#if os(visionOS)

    /// Update projection and rotation
    public func updateEyeUniforms(_ layerDrawable: LayerRenderer.Drawable,
                                  _ cameraPos: vector_float4,
                                  _ label: String) {

        updateTripleBufferedUniform()

        let modelMatrix = updateRotation()
        let deviceAnchor = WorldTracking.shared.deviceAnchor
        let anchorOrigin = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        uniformEyes[0].eye.0 = uniformForEyeIndex(0, label)
        if layerDrawable.views.count > 1 {
            uniformEyes[0].eye.1 = uniformForEyeIndex(1)
        }

        MuLog.Log(label, interval: 4) {

            if layerDrawable.views.count > 1 {
                let eye0 = self.uniformEyes[0].eye.0
                let eye1 = self.uniformEyes[0].eye.1
                print(label)
                print("\t\(label) projection  ", "0:\(eye0.projection.script)  1:\(eye1.projection.script)")
                print("\t\(label) projection_ ", "0:\(viewProjection_(0).script)  1:\(viewProjection_(1).script)")
                print("\t\(label) tangents    ", "0:\(tangentsDepthStr(0))  1:\(tangentsDepthStr(1))")
                print("\t\(label) viewModel   ", "0:\(eye0.viewModel.script)")
            } else {
                let eye0 = self.uniformEyes[0].eye.0
                print(label)
                print("\t\(label) projection  ", "0:\(eye0.projection.script)")
                print("\t\(label) projection_ ", "0:\(viewProjection_(0).script)")
                print("\t\(label) tangents    ", "0:\(tangentsDepthStr(0))")
                print("\t\(label) viewModel   ", "0:\(eye0.viewModel.script)")
            }
            /// compare with Apple's Projection
            func viewProjection_(_ index: Int, reverseZ: Bool = true) -> simd_double4x4 {

                let view = layerDrawable.views[index]
                let xScale = Double((view.tangents[1] - view.tangents[0])/2)
                let yScale = Double((view.tangents[2] - view.tangents[3])/2)
                let zFar = Double(layerDrawable.depthRange.x)
                let zNear = Double(layerDrawable.depthRange.y)

                var zScale  : Double
                var wzScale : Double

                if zFar.isInfinite {
                    zScale = Double(-1)
                    wzScale = -2 * Double(-2 * zNear)
                } else {
                    let zRange = zFar - zNear
                    zScale  = (reverseZ ? -(zNear + zFar): -(zFar + zNear)) / zRange
                    wzScale = (reverseZ ? -zNear * zFar  : -zFar * zNear  ) / zRange
                }

                let P = simd_double4([ xScale, 0, 0, 0 ])
                let Q = simd_double4([ 0, yScale, 0, 0 ])
                let R = simd_double4([ 0, 0, zScale, reverseZ ? 1: -1])
                let S = simd_double4([ 0, 0, wzScale, 0 ])

                let mat = matrix_double4x4([P, Q, R, S])
                return mat
            }
            func tangentsDepthStr(_ index: Int) -> String {
                let view = layerDrawable.views[index]
                return "\(view.tangents.script); \(layerDrawable.depthRange.script)"

            }
        }

        func uniformForEyeIndex(_ index: Int, _ label: String? = nil) -> UniformEye {

            let view = layerDrawable.views[index]
            let projection = ProjectiveTransform3D(
                leftTangent   : Double(view.tangents[0]),
                rightTangent  : Double(view.tangents[1]),
                topTangent    : Double(view.tangents[2]),
                bottomTangent : Double(view.tangents[3]),
                nearZ         : Double(layerDrawable.depthRange.y),
                farZ          : Double(layerDrawable.depthRange.x),
                reverseZ      : true)

            let viewMatrix = (anchorOrigin * view.transform).inverse
            var viewModel = viewMatrix * modelMatrix

            if infinitelyFar {
                viewModel.columns.3 = simd_make_float4(0, 0, 0, 1)
            }
            let uniformEye = UniformEye(.init(projection), viewModel)

            return uniformEye
        }
        /// rotate model
        func updateRotation() -> matrix_float4x4 {
            //???? rotation += 0.01
            let rotationAxis = SIMD3<Float>(1, 1, 0)
            let rotationMat = rotateQuat(radians: rotation, axis: rotationAxis)
            let translationMat = translateQuat(cameraPos)
            return translationMat * rotationMat
        }
    }
    #endif
    /// Update projection and rotation
    public func updateEyeUniforms(_ projection: matrix_float4x4,
                                  _ viewModel: matrix_float4x4) {

        updateTripleBufferedUniform()

        self.uniformEyes[0].eye.0 = UniformEye(projection, viewModel)
    }

    func updateTripleBufferedUniform() {

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
