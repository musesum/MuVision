
import Collections
import Metal
import MetalKit
import MuFlo
#if os(visionOS)
import CompositorServices
#endif
public enum ResourceType: String { case unknown, texture, buffer, vertex, fragment }


open class PipeNode: FloId, Equatable {

    public var pipeline: Pipeline
    public var shader: Shader?
    
    public var pipeName: String
    public var pipeFlo: Flo
    public var pipeChildren = [PipeNode]()

    public init(_ pipeline : Pipeline,
                _ pipeFlo  : Flo) {

        self.pipeName = pipeFlo.name
        self.pipeline = pipeline
        self.pipeFlo  = pipeFlo
        super.init()
        
        pipeFlo.children
            .filter { $0.val("on") != nil }
            .forEach { pipeline.makePipeNode($0, self) }
    }

    public func runCompute(_ computeEnc: MTLComputeCommandEncoder,
                           _ logging: inout String) {
        
        if let computeNode = self as? ComputeNode {

            logging += computeNode.pipeName + " -> "
            computeNode.updateUniforms()
            computeNode.computeNode(computeEnc)
        }
        pipeChildren
            .filter { $0.pipeFlo.val("on") ?? 0 > 0 }
            .forEach { $0.runCompute(computeEnc, &logging) }
    }
    public func runRender(_ renderEnc: MTLRenderCommandEncoder,
                          _ logging: inout String) {
        
        if let renderNode = self as? RenderNode {
            logging += renderNode.pipeName + " -> "
            renderNode.updateUniforms()
            renderNode.renderNode(renderEnc)
        }
        pipeChildren
            .filter { $0.pipeFlo.val("on") ?? 0 > 0 }
            .forEach { $0.runRender(renderEnc, &logging) }
    }

    open func makeRenderState(_ metalVD: MTLVertexDescriptor) -> MTLRenderPipelineState? {
        guard let shader else { return err("shaderFunc == nil") }

        let pd = MTLRenderPipelineDescriptor()
        pd.label = pipeFlo.name
        pd.vertexFunction   = shader.vertexFunction
        pd.fragmentFunction = shader.fragmentFunction
        pd.vertexDescriptor = metalVD
        pd.colorAttachments[0].pixelFormat = MetalRenderPixelFormat
        pd.depthAttachmentPixelFormat = .depth32Float
        #if targetEnvironment(simulator)
        #elseif os(visionOS )
        pd.maxVertexAmplificationCount = 2
        #endif
        //????? this is the only difference with CubeNode and FlatNode
        // alpha blend
        pd.colorAttachments[0].isBlendingEnabled = true
        pd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pd.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            return try pipeline.device.makeRenderPipelineState(descriptor: pd)
        } catch {
            return err("\(error)")
        }

        func err(_ err: String) -> MTLRenderPipelineState? {
            PrintLog("⁉️ makeRenderState err: \(err)")
            return nil
        }
    }
    
    public static func == (lhs: PipeNode, rhs: PipeNode) -> Bool { return lhs.id == rhs.id }
   
    open func renderNode(_ renderEnc: MTLRenderCommandEncoder) { }
    open func updateUniforms() {}
    open func makeResources() {}

#if os(visionOS)
    open func updateUniforms(_ drawable: LayerRenderer.Drawable,
                             _ deviceAnchor: DeviceAnchor?) {
        updateUniforms()
    }
    public func runRender(_ renderEnc: MTLRenderCommandEncoder,
                          _ drawable:  LayerRenderer.Drawable,
                          _ deviceAnchor: DeviceAnchor?,
                          _ logging: inout String) {

        if let renderNode = self as? RenderNode {
            logging += renderNode.pipeName + " -> "
            renderNode.updateUniforms(drawable, deviceAnchor)
            renderNode.renderNode(renderEnc)
        }
        pipeChildren
            .filter { $0.pipeFlo.val("on") ?? 0 > 0 }
            .forEach { $0.runRender(renderEnc, drawable, deviceAnchor, &logging) }
    }
#endif
}

extension PipeNode {
    public var cgImage: CGImage? { get {
        if let tex =  pipeline.layer.nextDrawable()?.texture,
           let img = tex.toImage() {
            return img
        } else {
            return nil
        }
    }}
}

