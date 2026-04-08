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
        pipeline.resizeNodes.append(makeResources)
    }

    override public func makeShader() {

        shader = Shader(pipeline,
                        file     : "render.map.flat",
                        vertex   : "flatVertex",
                        fragment : "flatFragment")

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        guard let shader else { return }
        let pd = MTLRenderPipelineDescriptor()
        pd.label = pipeFlo˚.name
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
    }
    
    override open func renderShader(
        _ encoder: MTLRenderCommandEncoder,
        _ state: RenderState) {
            
            guard let renderPipelineState else { return }
        let layer = pipeline.layer

        let portSize = SIMD2<Float>(layer.drawableSize)
        encoder.setViewport(MTLViewport(portSize))
        encoder.setRenderPipelineState(renderPipelineState)

        encoder.setVertexBuffer (vertBuf,          offset: 0, index: 0)
        encoder.setVertexBuffer (pipeline.drawBuf, offset: 0, index: 1)
        encoder.setVertexBuffer (pipeline.clipBuf, offset: 0, index: 2)
        encoder.setFragmentTexture(inTex˚, index: 0)

        // cull stencil
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        func err(_ err: String) {
            PrintLog("⁉️ FlatmapNode::renderNode err \(err)")
        }
    }
    
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {

        let inAdr = inTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr))"
        super.logShader(&logging, inOut)
    }
}
