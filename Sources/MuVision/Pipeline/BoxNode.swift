// created by musesum on 8/31/25

import RealityKit
import ModelIO
import MetalKit
import MuFlo

public class BoxNode: CubeNode, @unchecked Sendable { // box
    var queues: [TextureResource.DrawableQueue]?

    override public func makePipeline() {

        shader = Shader(pipeline,
                        file: "render.map.cube",
                        vertex: "cubeBoxVertex",
                        fragment: "cubeIndexFragment")

        if let shader {
            let pd = MTLRenderPipelineDescriptor()
            pd.label = "CubeBox"
            pd.vertexFunction   = shader.vertexFunction
            pd.fragmentFunction = shader.fragmentFunction
            // use vertex_id; no attributes needed for fullscreen quad
            pd.vertexDescriptor = nil
            pd.colorAttachments[0].pixelFormat = .bgra8Unorm
            pd.depthAttachmentPixelFormat = .depth32Float
            renderPipelineState = try? pipeline.device.makeRenderPipelineState(descriptor: pd)
        }
    }

    // for both metal and visionOS reflection
    override public func updateUniforms() {
        super.updateUniforms()
        boxFaces(to: queues)
        TimeLog("BoxNode::"+#function, interval: 4) { P("⬜︎ boxNode") }
    }


    /// write cube faces to RealityKit DrawableQueue
    public func boxFaces(to queues: [TextureResource.DrawableQueue]?) {
        let queues = queues ?? self.queues
        guard let queues, queues.count == 6,
              let inTex˚, let cudex˚ else { return }

        if self.queues == nil { self.queues = queues }

        // acquire drawables
        let drawables = queues.compactMap { try? $0.nextDrawable() }
        guard drawables.count == 6,
              let renderPipelineState,
              let depthTex = pipeline.updateDepthTex(
                drawables[0].texture.width,
                drawables[0].texture.height) else { return }

        let commandBuf = pipeline.commandQueue.makeCommandBuffer()!

        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].loadAction  = .dontCare
        rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 0)
        rp.depthAttachment.texture     = depthTex
        rp.depthAttachment.loadAction  = .dontCare
        rp.depthAttachment.storeAction = .dontCare
        rp.depthAttachment.clearDepth  = 1.0

        for face in 0..<6 {

            rp.colorAttachments[0].texture = drawables[face].texture

            let re = commandBuf.makeRenderCommandEncoder(descriptor: rp)!
            re.setRenderPipelineState(renderPipelineState)
            re.setFragmentTexture(inTex˚, index: 0)
            re.setFragmentTexture(cudex˚, index: 1)
            re.setFragmentBuffer (mixcube˚, index: 0)

            var faceIndex: UInt32 = UInt32(face)
            let size = MemoryLayout<UInt32>.size
            re.setVertexBytes(&faceIndex, length: size, index: 10)

            re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6) // full-screen quad
            re.endEncoding()
        }
        drawables.forEach { $0.present() }
        commandBuf.commit()

    }
}

