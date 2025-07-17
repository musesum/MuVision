// created by musesum on 7/30/24
#if os(visionOS)
import MuFlo
import Spatial
import CompositorServices

extension EyeBuf {
    /// Update projection and rotation
    @available(visionOS 2.0, *)
    public func updateEyeUniforms(_ drawable: LayerRenderer.Drawable,
                                  _ deviceAnchor: DeviceAnchor?,
                                  _ cameraPos: vector_float4,
                                  _ label: String) {

        nextTripleUniformBuffer()

        let anchorOrigin = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        eyes[0].eye.0 = uniformForEyeIndex(0, label)
        if drawable.views.count > 1 {
            eyes[0].eye.1 = uniformForEyeIndex(1)
        }

        NoTimeLog(#function, interval: 4) {
            let tab = "\t\(label[0...1])"

            if drawable.views.count > 1 {
                let view0 = drawable.views[0]
                let view1 = drawable.views[1]
                let orient0 =  (anchorOrigin * view0.transform).inverse
                let orient1 =  (anchorOrigin * view1.transform).inverse
                let eye0 = self.eyes[0].eye.0
                let eye1 = self.eyes[0].eye.1
                print(tab+" projection  0:\(eye0.projection.digits(-2))")
                print(tab+"             1:\(eye1.projection.digits(-2))")
                print(tab+" orientation 0:\(orient0.digits(-2))")
                print(tab+"             1:\(orient1.digits(-2))")
                print("\t👁️ viewModel   ", "0:\(eye0.viewModel.digits(-2))")
            } else {
                let view0 = drawable.views[0]
                let orient0 =  (anchorOrigin * view0.transform).inverse

                let eye0 = self.eyes[0].eye.0 
                print(tab+" projection  0:\(eye0.projection.digits(-2))")
                print(tab+" orientation 0:\(orient0.digits(-2))")
                print(tab+" viewModel   0:\(eye0.viewModel.digits(-2))")
            }
            func tangentsDepthStr(_ index: Int) -> String {
                let projection = drawable.computeProjection(viewIndex: index)
                return "\(projection.digits(-2)); \(drawable.depthRange.digits(-2))"
            }
        }

        func uniformForEyeIndex(_ index: Int,
                                _ label: String? = nil) -> UniformEye {
            
            let view = drawable.views[index]
            let projection = drawable.computeProjection(viewIndex: index)

            let orientation = (anchorOrigin * view.transform).inverse
            var viewModel = orientation

            if infinitelyFar {
                viewModel = orientation
                viewModel.columns.3 = simd_make_float4(0, 0, 0, 1)
            } else {
                viewModel *= updateRotation() //??
            }
            let uniformEye = UniformEye(.init(projection), viewModel)

            return uniformEye
        }
        /// rotate model
        func updateRotation() -> matrix_float4x4 {
            //?? rotation += 0.01
            return cameraPos.translate * SIMD3<Float>(1, 1, 0).rotate(radians: rotation)
        }
    }
}
#endif

