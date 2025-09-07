// created by musesum on 8/31/25


#if os(visionOS)
import RealityKit
import ModelIO
import MetalKit
import CompositorServices

extension CubeNode { // box

    internal func makeBoxPipeline() {
        let library = pipeline.library!
        let pd = MTLRenderPipelineDescriptor()
        pd.label = "CubeBox"
        pd.vertexFunction   = library.makeFunction(name: "cubeBoxVertex")
        pd.fragmentFunction = library.makeFunction(name: "cubeIndexFragment")
        pd.vertexDescriptor = nil // use vertex_id; no attributes needed for fullscreen quad
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pd.depthAttachmentPixelFormat = .depth32Float
        boxPipelineState = try! pipeline.device.makeRenderPipelineState(descriptor: pd)
    }

    /// write cube faces to RealityKit DrawableQueue
    public func boxFaces(to queues: [TextureResource.DrawableQueue]) {
        guard queues.count == 6,
              let inTex˚, let cudex˚ else { return }

        // acquire drawables
        let drawables = queues.compactMap { try? $0.nextDrawable() }
        guard drawables.count == 6 else { return }

        // scratch color0 (throwaway)
        let width  = drawables[0].texture.width
        let height = drawables[0].texture.height

        let dd = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        dd.usage = .renderTarget
        dd.storageMode = .memoryless
        guard let depthTex = pipeline.device.makeTexture(descriptor: dd) else { return }

        let commandBuf = pipeline.commandQueue.makeCommandBuffer()!
        for face in 0..<6 {
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture     = drawables[face].texture
            rp.colorAttachments[0].loadAction  = .dontCare
            rp.colorAttachments[0].storeAction = .store
            rp.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 0)

            rp.depthAttachment.texture     = depthTex
            rp.depthAttachment.loadAction  = .dontCare
            rp.depthAttachment.storeAction = .dontCare
            rp.depthAttachment.clearDepth  = 1.0

            let re = commandBuf.makeRenderCommandEncoder(descriptor: rp)!
            re.setRenderPipelineState(boxPipelineState)
            re.setFragmentTexture(inTex˚, index: 0)
            re.setFragmentTexture(cudex˚, index: 1)
            re.setFragmentBuffer (mixcube˚, index: 0)

            var faceIndex: UInt32 = UInt32(face)
            let size = MemoryLayout<UInt32>.size
            re.setVertexBytes(&faceIndex, length: size, index: 10)

            re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6) // full-screen quad
            re.endEncoding()
        }
        commandBuf.commit()
        commandBuf.waitUntilCompleted()
        drawables.forEach { $0.present() }
    }
}
#endif
