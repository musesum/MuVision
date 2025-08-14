// created by musesum on 7/13/24
import Metal
import MuFlo

extension Flo { // MTLBuffer

    public func updateMtlBuffer() {

        if let device = MTLCreateSystemDefaultDevice(),
           let nums = exprs?.getFloatNums() {

            device.updateFloMTLBuffer(self, nums)
        }
    }

    /// update Flo expression and Flo's MTL shader uniforms
    public func updateFloShader<T: BinaryFloatingPoint>(_ nameNums: [(String,T)]) {

        // update Flo Exprs
        if let exprs {
            exprs.setFromNameNums(nameNums, [], Visitor(0))
        }

        // extract nums and update Flo's MTL shader uniform buffer
        if let device = MTLCreateSystemDefaultDevice() {
            device.updateFloMTLBuffer(self, nameNums.map { $0.1 })
        }
    }
}

extension MTLDevice {
    
    func updateFloMTLBuffer<T: BinaryFloatingPoint>(_ flo: Flo, _ nums: [T]) {
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
}
