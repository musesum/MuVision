//  created by musesum on 1/6/25.

import UIKit
import MuFlo

open class TouchLog {
    
    private var posX: ClosedRange<CGFloat>?
    private var posY: ClosedRange<CGFloat>?
    private var radi: ClosedRange<CGFloat>?
    
    public init() {}
    
    public func log(_ phase: UITouch.Phase,
                    _ nextXY: CGPoint,
                    _ radius: CGFloat) {
        
        switch phase {
        case .began : logNow("\n👍🟢") ; resetRanges()
        case .moved : logNow("🫰🔷")   ; setRanges()
        case .ended : logNow("🖐️🛑")   ; setRanges(); logRanges()
        default     : PrintLog("🖐️⁉️")
        }
        
        func logNow(_ msg: String) {
            //PrintLog("\(msg)(\(nextXY.x.digits(0...2)), \(nextXY.y.digits(0...2)), \(radius.digits(0...2)))", terminator: " ")
        }
        
        func resetRanges() {
            posX = nil
            posY = nil
            radi = nil
            setRanges()
        }
        
        func setRanges() {
            if posX == nil { posX = nextXY.x ... nextXY.x }
            else if let xx = posX { posX = min(xx.lowerBound, nextXY.x)...max(xx.upperBound, nextXY.x) }
            if posY == nil { posY = nextXY.y ... nextXY.y}
            else if let yy = posY {  posY = min(yy.lowerBound, nextXY.y)...max(yy.upperBound, nextXY.y) }
            if radi == nil { radi = radius ... radius }
            else if let rr = radi { radi = min(rr.lowerBound, radius)...max(rr.upperBound, radius) }
        }
        
        func logRanges() {
            if let posX, let posY, let radi {
                let xStr = "\(posX.lowerBound.digits(0))…\(posX.upperBound.digits(0))"
                let yStr = "\(posY.lowerBound.digits(0))…\(posY.upperBound.digits(0))"
                let rStr = "\(radi.lowerBound.digits(0))…\(radi.upperBound.digits(0))"
                NoDebugLog { P("👐 (\(xStr), \(yStr), \(rStr))") }
            }
        }
    }
}