// created by musesum on 7/13/24
import Metal
import MuFlo

extension Flo { // MTLBuffer

    /// a shift flo whose layer is still wrapping: the eased value the Metal
    /// buffer carries -- getFloatNums takes each scalar's tween, below -- is
    /// off the 0.5 0.5 centre that means still. Never the touch target:
    /// while sky.main.anim carries the azimuth pad home the target is
    /// already at centre, and a pass gated on that stops the layer dead
    /// while the pad's tween thumb is still gliding. At rest the plugin
    /// lands the tween on the target, so a still layer costs nothing
    public var shiftWrapping: Bool {
        guard let exprs else { return false }
        let x = exprs["x", .tween] ?? 0.5
        let y = exprs["y", .tween] ?? 0.5
        return abs(x - 0.5) > 0.001 || abs(y - 0.5) > 0.001
    }

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
