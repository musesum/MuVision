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

    func updateBuffer<T: BinaryFloatingPoint>(_ any: Any?,_ nums: [T]) {
        if let buffer = any as? MTLBuffer {
            let size =  nums.count * MemoryLayout<T>.stride
            nums.withUnsafeBytes { rawBufferPointer in
                guard let baseAddress = rawBufferPointer.baseAddress else { return }
                buffer.contents().copyMemory(from: baseAddress, byteCount: size)
            }
        }
    }

    func updateFloNumsBuffer<T: BinaryFloatingPoint>(_ flo: Flo, _ nums: [T]) {
        let newSize = nums.count * MemoryLayout<T>.stride
        nums.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            if let buffer = flo.buffer,
               buffer.allocatedSize <= newSize {
                buffer.contents().copyMemory(from: baseAddress, byteCount: newSize)
            } else {
                let buffer = makeBuffer(bytes: baseAddress, length: newSize, options: [])
                buffer?.label = flo.path(2)
                flo.buffer = buffer
            }
        }
    }
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
