// created by musesum on 7/13/24
import Metal
import MuFlo

extension Flo {

    public func updateMtlBuffer() {
        
        if let device = MTLCreateSystemDefaultDevice(),
           let nums = exprs?.getFloatNums() {
            
            device.updateFloNumsBuffer(self, nums)
        }
    }

    public func updateFloScalars(_ any: Any) {

        if let exprs {
            // update old expression
            exprs.setFromAny(any, [], Visitor(0))
        } else {
            // create new expression
            exprs = makeAnyExprs(any)
            if let nums = exprs?.getFloatNums() {
                updateNums(nums)
            }
        }

        // create or update MTLResource
        switch any {
        case let v as Double   : updateFloatNums([v])
        case let v as [Double] : updateFloatNums(v)
        case let v as Float    : updateNums([v])
        case let v as [Float]  : updateNums(v)
        case let v as CGPoint  : updateNums(v.floats())
        case let v as CGSize   : updateNums(v.floats())
        case let v as CGRect   : updateNums(v.floats())

        default:  TimeLog(#function, interval: 4) { P("⁉️ Flo::\(#function) unknown any \(any)")}
        }

        func updateFloatNums(_ nums: [Double]) {
            var floats = [Float]()
            for num in nums {
                let float = Float(num)
                floats.append(float)
            }
            updateNums(nums)
        }
        func updateNums<T: BinaryFloatingPoint>(_ nums: [T]) {
            if let device = MTLCreateSystemDefaultDevice() {
                device.updateFloNumsBuffer(self, nums)
            }
        }
    }
}
