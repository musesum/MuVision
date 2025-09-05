// created by musesum on 8/31/25


#if os(visionOS)
import RealityKit
import ModelIO
import MetalKit
import CompositorServices

extension CubeNode { // bake

    internal func makeBakePipeline() {
        let library = pipeline.library!
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "CubeIndex-Bake-MRT"
        descriptor.vertexFunction   = library.makeFunction(name: "cubeBakeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cubeIndexFragment_mrt")
        descriptor.vertexDescriptor = nil // use vertex_id; no attributes needed for fullscreen quad
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[1].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        bakePipelineState = try! pipeline.device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// MRT-bake: write each cube face into a RealityKit DrawableQueue texture using the same fragment.
    func bakeFacesMRT(to queues: [TextureResource.DrawableQueue]) {
        guard queues.count == 6,
              let inTex˚, let cudex˚ else { return }

        // acquire drawables
        let drawables = queues.compactMap { try? $0.nextDrawable() }
        guard drawables.count == 6 else { return }

        // scratch color0 (throwaway)
        let width  = drawables[0].texture.width
        let height = drawables[0].texture.height

        if scratch0 == nil || scratch0!.width != width || scratch0!.height != height {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            textureDescriptor.usage = .renderTarget
            textureDescriptor.storageMode = .memoryless
            scratch0 = pipeline.device.makeTexture(descriptor: textureDescriptor)
        }

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .memoryless
        guard let depthTexture = pipeline.device.makeTexture(descriptor: depthDescriptor) else { return }

        let commandBuffer = pipeline.commandQueue.makeCommandBuffer()!
        for face in 0..<6 {
            let renderPass = MTLRenderPassDescriptor()
            renderPass.colorAttachments[0].texture     = scratch0
            renderPass.colorAttachments[0].loadAction  = .dontCare
            renderPass.colorAttachments[0].storeAction = .dontCare

            renderPass.colorAttachments[1].texture     = drawables[face].texture
            renderPass.colorAttachments[1].loadAction  = .dontCare
            renderPass.colorAttachments[1].storeAction = .store
            renderPass.colorAttachments[1].clearColor  = MTLClearColorMake(0, 0, 0, 0)

            renderPass.depthAttachment.texture     = depthTexture
            renderPass.depthAttachment.loadAction  = .clear
            renderPass.depthAttachment.storeAction = .dontCare
            renderPass.depthAttachment.clearDepth  = 1.0

            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!
            renderEncoder.setRenderPipelineState(bakePipelineState)

            // resources match your main pass
            renderEncoder.setFragmentTexture(inTex˚, index: 0)
            renderEncoder.setFragmentTexture(cudex˚, index: 1)
            renderEncoder.setFragmentBuffer (mixcube˚, index: 0)

            var faceIndex: UInt32 = UInt32(face)
            renderEncoder.setVertexBytes(&faceIndex, length: MemoryLayout<UInt32>.size, index: 10)

            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6) // full-screen quad
            renderEncoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        drawables.forEach { $0.present() }
    }
}
#endif
