// created by musesum on 2/22/19.

import Foundation
import Metal
import MetalKit
import QuartzCore
#if os(visionOS)
import CompositorServices
#endif
import MuFlo

public class FlatNode: RenderNode {

    private var inTex˚  : Flo?
    private var eyes˚   : Flo?
    private var vertBuf : MTLBuffer?

    override public init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        super.init(pipeline, pipeNode˚)

        inTex˚ = pipeNode˚.superBindPath("in")
        makeRenderPipeline()
        makeResources()
        pipeline.resizeNodes.append(makeResources)
    }

    func makeRenderPipeline() {

        shader = Shader(pipeline,
                        file     : "render.map.flat",
                        vertex   : "flatVertex",
                        fragment : "flatFragment")

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        guard let shader else { return }
        let pd = MTLRenderPipelineDescriptor()
        pd.label = pipeNode˚.name
        pd.vertexFunction = shader.vertexFunction
        pd.fragmentFunction = shader.fragmentFunction
        pd.colorAttachments[0].pixelFormat = MuRenderPixelFormat
        pd.depthAttachmentPixelFormat = .depth32Float
        #if targetEnvironment(simulator)
        #elseif os(visionOS)
        pd.maxVertexAmplificationCount = 2
        #endif
        do { renderPipelineState = try
            device.makeRenderPipelineState(descriptor: pd) }
        catch {
            PrintLog("⁉️ FlatmapNode::\(#function) \(error)")
        }
    }

    override public func makeResources() {

        let layer = pipeline.layer
        let device = pipeline.device
        // from center point +/- w2,h2
        let w2 = Float(layer.drawableSize.width / 2)
        let h2 = Float(layer.drawableSize.height / 2)

        let vertices: [FlatVertex] = [
            // (position texCoord)
            FlatVertex( w2,-h2, 1, 1),
            FlatVertex(-w2,-h2, 0, 1),
            FlatVertex(-w2, h2, 0, 0),
            FlatVertex( w2,-h2, 1, 1),
            FlatVertex(-w2, h2, 0, 0),
            FlatVertex( w2, h2, 1, 0)]

        let memSize = MemoryLayout<FlatVertex>.size * vertices.count
        let buffer = device.makeBuffer(bytes: vertices,
                                       length: memSize,
                                       options: .storageModeShared)
        buffer?.label = "FlatVertices"
        vertBuf = buffer

        super.makeResources()
    }
    
    override open func renderShader(_ renderEnc: MTLRenderCommandEncoder,
                                    _ renderState: RenderState) {

        guard let renderPipelineState else { return }
        let layer = pipeline.layer

        let portSize = SIMD2<Float>(layer.drawableSize)
        renderEnc.setViewport(MTLViewport(portSize))
        renderEnc.setRenderPipelineState(renderPipelineState)

        renderEnc.setVertexBuffer (vertBuf,          offset: 0, index: 0)
        renderEnc.setVertexBuffer (pipeline.drawBuf, offset: 0, index: 1)
        renderEnc.setVertexBuffer (pipeline.clipBuf, offset: 0, index: 2)
        renderEnc.setFragmentTexture(inTex˚, index: 0)

        // cull stencil
        renderEnc.setCullMode(.none)
        renderEnc.setFrontFacing(.clockwise)
        renderEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        func err(_ err: String) {
            PrintLog("⁉️ FlatmapNode::renderNode err \(err)")
        }
    }
}
