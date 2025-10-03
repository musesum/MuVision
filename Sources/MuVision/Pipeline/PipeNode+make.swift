// created by musesum on 9/8/25

import MetalKit
import MuFlo // PrintLog

extension PipeNode { // make
    
    public func makeRenderState(_ metalVD: MTLVertexDescriptor) -> MTLRenderPipelineState? {
        guard let shader else { return err("shaderFunc == nil") }
        
        let pd = MTLRenderPipelineDescriptor()
        pd.label = pipeFlo˚.name
        pd.vertexFunction   = shader.vertexFunction
        pd.fragmentFunction = shader.fragmentFunction
        pd.vertexDescriptor = metalVD
        pd.colorAttachments[0].pixelFormat = MuRenderPixelFormat
        pd.depthAttachmentPixelFormat = .depth32Float
#if targetEnvironment(simulator)
#elseif os(visionOS )
        pd.maxVertexAmplificationCount = 2
#endif
        //?? alpha blend is the only difference with CubeNode and FlatNode
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
    public var cgImage: CGImage? { get {
        if let tex =  pipeline.layer.nextDrawable()?.texture,
           let img = tex.toImage() {
            return img
        } else {
            return nil
        }
    }}
    public func makeComputeTex(size: CGSize,
                               label: String?,
                               format: MTLPixelFormat? = nil) -> MTLTexture? {
        let td = MTLTextureDescriptor()
        td.pixelFormat = MuComputePixelFormat
        td.width = Int(size.width)
        td.height = Int(size.height)
        td.usage = [.shaderRead, .shaderWrite]
        let tex = pipeline.device.makeTexture(descriptor: td)
        if let label {
            tex?.label = label
        }
        return tex
    }
    public func paletteTexture(_ flo: Flo?) {
        
        guard let flo else { return }
        let size = CGSize(width: 256, height: 1)
        
        let path = flo.path(3)
        if let tex = makeComputeTex(size: size,
                                    label: path,
                                    format: MuComputePixelFormat) {
            flo.texture = tex
            flo.reactivate()
            DebugLog { P("🧭 paletteTexture\(size.digits(0)) \(path)") }
        }
    }
    /// make new texture, or remake an old one if size changes.
    public func displaceTexture(_ flo: Flo?) {
        
        guard let flo else { return }
        
        let size = pipeline.pipeSize
        if flo.texture?.width == Int(size.width),
           flo.texture?.height == Int(size.height) { return }
        
        let path = flo.path(3)
        if let tex = makeComputeTex(size: size,
                                    label: path,
                                    format: MuHeightPixelFormat) {
            flo.texture = tex
            flo.reactivate()
            pipeline.rotatable[path] = (tex, self, flo)
            DebugLog { P("🧭 heightTexture\(size.digits(0)) \(path)") }
        }
    }
    
    /// make new texture, or remake an old one if size changes.
    public func computeTexture(_ flo: Flo?) {
        
        guard let flo else { return }
        
        let size = pipeline.pipeSize
        if flo.texture != nil { return }
        
        let path = flo.path(3)
        if let tex = makeComputeTex(size: size,
                                    label: path,
                                    format: MuComputePixelFormat) {
            flo.texture = tex
            flo.reactivate()
            pipeline.rotatable[path] = (tex, self, flo)
            DebugLog { P("🧭 updateTexture\(size.digits(0)) \(path)") }
        }
    }
    
}
