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

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        self.cubeMesh = CubeMesh(pipeline.renderState)
        self.viaIndex = true
        super.init(pipeline, pipeFlo˚)
        
        inTex˚    = pipeFlo˚.superBindPath("in")
        cudex˚    = pipeFlo˚.superBindPath("cudex")
        displace˚ = pipeFlo˚.superBindPath("displace")
        mixcube˚  = pipeFlo˚.superBindPath("mixcube")
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
        cubeMesh.eyeBuf = EyeBuf("CubeEyes", far: false)
    }

    override open func renderShader(
        _ renderEnc: MTLRenderCommandEncoder,
        _ renderState: RenderState) {

            guard let renderPipelineState else { return }

            cubeMesh.eyeBuf?.setUniformBuf(renderEnc)
            if let mixcube˚ {
            #if os(visionOS) //....
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
        let drawableSize = pipeline.layer.drawableSize

        Task {
            let orientation = await Motion.shared.updateDeviceOrientation()

            let projection = project4x4(drawableSize)
            TimeLog("CubeNode::"+#function, interval: 4) {
                P("👁️ cubeNode") //\(orientation.digits(1))")
                //print("\t👁️c projection  ", projection.digits)
            }
            eyebuf.updateEyeUniforms(projection, orientation)
        }
    }

#if os(visionOS)

    /// Update projection and rotation
    override public func updateUniforms(_ drawable : LayerRenderer.Drawable,
                                        _ anchor   : DeviceAnchor?) {

        let cameraPos = vector_float4([0, 0,  -4, 1])
        cubeMesh.eyeBuf?.updateEyeUniforms(drawable, anchor, cameraPos, "👁️C⃝ube")
    }

#endif

}
