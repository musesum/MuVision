// created by musesum on 7/30/24
#if os(visionOS)
import MuFlo
import Spatial
import CompositorServices

extension EyeBuf {
    /// Update projection and rotation for visionOS immersive space
    public func updateVisionEyeUniforms(
        _ drawable: LayerRenderer.Drawable,
        _ anchor: DeviceAnchor?,
        _ zoom: Float,
        _ label: String) {

        nextTripleUniformBuffer()

        let anchorOrigin = anchor?.originFromAnchorTransform ?? matrix_identity_float4x4
        // the range's floor in mixed; in full immersion the head stays inside
        // the cube; the last floorBand of zoom eases into it
        let floor = Self.zoomFloor(head: anchorOrigin.columns.3.xyz,
                                   cubeRadius: CubeModel.radius,
                                   full: ImmersionModel.fullNow)
        let zoomNow = Self.zoomEased(zoom, floor: floor)
        // plato.cube's turn: yaw, pitch and the face eases, about the model's
        // own centre; the head's pose is the drawable's, so no device turn
        let turn = CubeNav.shared.view(matrix_identity_float4x4)

        eyes[0].eye.0 = uniformForEyeIndex(0, label)
        if drawable.views.count > 1 {
            eyes[0].eye.1 = uniformForEyeIndex(1)
        }
        visionModel = modelTransform()
        visionHead = anchorOrigin.columns.3.xyz

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
                // Skybox/stars: remove translation so both eyes see same background
                viewModel = orientation
                viewModel.columns.3 = simd_make_float4(0, 0, 0, 1)
            } else {
                // Place and size the model relative to the camera
                viewModel *= modelTransform()
            }
            let uniformEye = UniformEye(projection, viewModel)

            return uniformEye
        }

        /// Renamed from updateRotation
        func modelTransform() -> matrix_float4x4 {
            let distance = Self.placeFar - zoomNow * Self.placeRun // metres ahead (−Z)
            let scale = Self.scaleMin + zoomNow
            let yOffset = Self.placeUp

            let translate = SIMD4<Float>(0, yOffset, -distance, 1).translate
            let scaleM = scale4x4(scale)

            // translate (place it), then turn, then scale about local origin.
            return translate * turn * scaleM
        }

        /// Standard uniform scaling matrix (avoid using Float.scale in Simd+ext)
        func scale4x4(_ s: Float) -> matrix_float4x4 {
            let X = vector_float4(s, 0, 0, 0)
            let Y = vector_float4(0, s, 0, 0)
            let Z = vector_float4(0, 0, s, 0)
            let W = vector_float4(0, 0, 0, 1)
            return matrix_float4x4(columns: (X, Y, Z, W))
        }
    }
}
#endif
