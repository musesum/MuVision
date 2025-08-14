// created by musesum on 7/13/24
import Metal
import MuFlo

extension Flo { // MTLBuffer

    public func updateMtlBuffer() {

        if let device = MTLCreateSystemDefaultDevice(),
           let nums = exprs?.getFloatNums() {

            device.updateFloNumsBuffer(self, nums)
        }
    }
    public func updateFloMTLNums<T: BinaryFloatingPoint>(_ nums: [T]) {
        if let exprs {
            exprs.setFromAny(nums, [], Visitor(0))
        } else {
            if let device = MTLCreateSystemDefaultDevice() {
                device.updateFloNumsBuffer(self, nums)
            }
        }
    }
    public func updateFloMTLNameNums<T: BinaryFloatingPoint>(_ nameNums: [(String,T)]) {
        if let exprs {
            exprs.setFromAny(nameNums, [], Visitor(0))
        }
        var nums = [T]()
        for (_,v) in nameNums {
            nums.append(v)
        }

        if let device = MTLCreateSystemDefaultDevice() {
            device.updateFloNumsBuffer(self, nums)
        }
    }
}

extension MTLDevice {
    
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
}
