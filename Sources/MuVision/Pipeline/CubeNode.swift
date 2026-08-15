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
    internal var zoom˚      : Flo?
    internal var zoom       : Float = 0

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        self.cubeMesh = CubeMesh(pipeline.renderState)
        self.viaIndex = true
        super.init(pipeline, pipeFlo˚)

        inTex˚    = pipeFlo˚.superBindPath("in")
        cudex˚    = pipeFlo˚.superBindPath("cudex")
        mixcube˚  = pipeFlo˚.superBindPath("mixcube")
        zoom˚     = pipeFlo˚.getRoot().bind("plato.zoom") { f,_ in
            self.zoom = f.float
        }
    }
    
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
            eyebuf.updateMetalEyeUniforms(orientation)
        }
    }
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {

        let inAdr = inTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr))"
        super.logShader(&logging, inOut)
    }
#if os(visionOS)

    /// Update projection and rotation
    override public func updateUniforms(_ drawable : LayerRenderer.Drawable,
                                        _ anchor   : DeviceAnchor?) {
        cubeMesh.eyeBuf?.updateVisionEyeUniforms(drawable, anchor, zoom, "👁️C⃝ube")
    }

#endif

}
