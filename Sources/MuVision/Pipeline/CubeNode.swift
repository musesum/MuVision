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
    internal var displace˚  : Flo? // unused
    internal var lastAspect : Aspect?
    internal var zoom˚      : Flo?
    internal var zoom       : Float = 0

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        self.cubeMesh = CubeMesh(pipeline.renderState)
        self.viaIndex = true
        super.init(pipeline, pipeFlo˚)

        inTex˚    = pipeFlo˚.superBindPath("in")
        cudex˚    = pipeFlo˚.superBindPath("cudex")
        displace˚ = pipeFlo˚.superBindPath("displace")
        mixcube˚  = pipeFlo˚.superBindPath("mixcube")
        zoom˚     = pipeFlo˚.getRoot().bind("plato.zoom") { f,_ in
            self.zoom = f.float
        }
    }
    
    override public func makePipeline() {
        shader = Shader(pipeline,
                        file: "render.map.cube",
                        vertex: "cubeVertex",
                        fragment: "cubeIndexFragment")
        renderPipelineState = makeRenderState(cubeMesh.mtlVD)
    }

    override open func makeResources() {

        makeCube()
        cubeMesh.eyeBuf = EyeBuf("CubeEyes", pipeline, far: false)
    }

    override open func renderShader(
        _ renderEnc: MTLRenderCommandEncoder,
        _ renderState: RenderState) {

            guard let renderPipelineState else { return }

            cubeMesh.eyeBuf?.setUniformBuf(renderEnc)
            if let mixcube˚ {
            #if os(visionOS)
            mixcube˚.setNameNums([("x", 1)], .fire) //....
            #endif
            mixcube˚.updateMtlBuffer()
        }
        //.. renderEnc.setFragmentTexture(displace˚,index: 3)
        renderEnc.setFragmentTexture(inTex˚,   index: 0)
        renderEnc.setFragmentTexture(cudex˚,   index: 1)
        renderEnc.setFragmentBuffer (mixcube˚, index: 0)

        renderEnc.setRenderPipelineState(renderPipelineState)
        cubeMesh.drawMesh(renderEnc, renderState)
        cudex˚?.reactivate()
    }

    // for both metal and visionOS reflection
    override public func updateUniforms() {
        guard let eyebuf = cubeMesh.eyeBuf else { return }

        Task {
            let orientation = await Motion.shared.updateDeviceOrientation()
            eyebuf.updateMetalEyeUniforms(orientation)
        }
    }

#if os(visionOS)

    /// Update projection and rotation
    override public func updateUniforms(_ drawable : LayerRenderer.Drawable,
                                        _ anchor   : DeviceAnchor?) {
        cubeMesh.eyeBuf?.updateVisionEyeUniforms(drawable, anchor, zoom, "👁️C⃝ube")
    }

#endif

}
