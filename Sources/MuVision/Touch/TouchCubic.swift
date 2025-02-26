
import QuartzCore
import MuFlo // CubicPoly

public struct TouchCubic {

    var x = CubicPoly<CGFloat>() // point x
    var y = CubicPoly<CGFloat>() // point y
    var r = CubicPoly<CGFloat>() // radius

    public mutating func addPointRadius(_ point  : CGPoint,
                                        _ radius : CGFloat,
                                        _ isDone : Bool   ) {
        x.addVal(point.x, isDone)
        y.addVal(point.y, isDone)
        r.addVal(radius,  isDone)
    }
    // get the maximum linear interval beteen p4's p[2] and p[3]
    func maximumMidInterval() -> CGFloat {
        return fmax(x.distance, y.distance)
    }

    public func drawPoints(_ drawPoint: TouchDrawPoint?)  {
        guard let drawPoint else { return }

        // choose longest interval between x and y axis for filling arc
        let longest = max(1, x.distance, y.distance)   // longest distance
        let increment = 1.0 / longest  // cover every pixel

        // iterate between 0 and 1
        for inter: CGFloat in stride(from: 0, to: 1, by: increment) {

            let xx = x.getInter(inter)
            let yy = y.getInter(inter)
            let rr = r.getInter(inter)
            drawPoint(CGPoint(x: xx, y: yy), rr)
        }
    }
}
