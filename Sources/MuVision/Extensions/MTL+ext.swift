// created by musesum on 11/19/24
import MuFlo
import Metal

#if os(visionOS)
public let MetalRenderPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
#else
public let MetalRenderPixelFormat = MTLPixelFormat.bgra8Unorm
#endif
public let MetalComputePixelFormat = MTLPixelFormat.bgra8Unorm


extension MTLDevice {
    
    public func makeComputeTex(size: CGSize,
                               label: String?,
                               format: MTLPixelFormat? = nil) -> MTLTexture? {
        let td = MTLTextureDescriptor()
        td.pixelFormat = format ?? MetalComputePixelFormat
        td.width = Int(size.width)
        td.height = Int(size.height)
        td.usage = [.shaderRead, .shaderWrite]
        let tex = makeTexture(descriptor: td)
        if let label {
            tex?.label = label
        }
        return tex
    }
}

