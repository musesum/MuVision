// created by musesum on 12/18/23

#if os(visionOS)

import Spatial
import CompositorServices

open class RenderLayerNode {
    
    private var renderer: RenderLayer
    private var renderPipe: MTLRenderPipelineState?
    public var mesh: MeshMetal?
    public var eyeBuf: UniformEyeBuf?
    
    public init(_ renderer: RenderLayer) {
        self.renderer = renderer
    }
    
    public func makePipeline(_ vertexName: String,
                             _ fragmentName: String) {
        
        let configuration = renderer.layerRenderer.configuration
        let library = renderer.library
        let device = renderer.device
        let colorFormat = configuration.colorFormat
        let depthFormat = configuration.depthFormat
        
        guard let mesh else { return err("\(#function) mesh")}

        do {
            let pd = MTLRenderPipelineDescriptor()
            
            pd.colorAttachments[0].pixelFormat = colorFormat
            pd.depthAttachmentPixelFormat = depthFormat
            
            pd.vertexFunction   = library.makeFunction(name: vertexName)
            pd.fragmentFunction = library.makeFunction(name: fragmentName)
            pd.vertexDescriptor = mesh.metalVD
            renderPipe = try device.makeRenderPipelineState(descriptor: pd)
            
        } catch let error {
            err("compile \(error.localizedDescription)")
        }
        
        func err(_ msg: String) {
            print("⁉️ error: \(msg)")
        }
    }
}
#endif 
