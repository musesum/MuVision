//  created by musesum on 7/30/19.

import Foundation

public struct Rgb {

    public var r: Float // 0...1
    public var g: Float // 0...1
    public var b: Float // 0...1
    public var a: Float // = 1

    public init(r: Float, g: Float, b: Float, a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static func << (lhs: inout Rgb, rhs: Rgb) {
        let rfade = rhs.a
        let lfade = 1-rfade
        lhs.r = (lhs.r * lfade) + (rhs.r * rfade)
        lhs.g = (lhs.g * lfade) + (rhs.g * rfade)
        lhs.b = (lhs.b * lfade) + (rhs.b * rfade)
    }

    /// return 0..<360
    func hsv() -> Hsv {

        let Min = min(r, min(g, b))
        let Max = max(r, max(g, b))
        if  Max == 0 { return Hsv(0, 0, 0) }

        let delta = Max-Min
        let ss = delta/Max
        var hh = Float(0)
        let vv = Max

        if      r == Max { hh =       ( g - b ) / delta } // between yellow & magenta
        else if g == Max { hh = 2.0 + ( b - r ) / delta } // between cyan & yellow
        else             { hh = 4.0 + ( r - g ) / delta } // between magenta & cyan
        hh /= 60                // degrees
        if hh < 0 { hh += 1 }
        return Hsv(hh, ss, vv)
    }
    func script() -> String {
        return String(format: "(%02X %02X %02X %02X)",
                      Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))    }

    static func makeRamp(_ span: Int,
                         _ start: Rgb,
                         _ mid: Rgb,
                         _ end: Rgb,
                         _ log: Bool) -> [Rgb] {

        var result = [Rgb]()
        let span1 = span/2
        let span2 = span-span1
        let span1f = Float(span1)
        let span2f = Float(span2)

        for i in 0 ..< span1 {
            let factor = Float(i)/span1f
            let invFact = 1 - factor
            let rgb = Rgb(r: start.r * invFact + mid.r * factor,
                          g: start.g * invFact + mid.g * factor,
                          b: start.b * invFact + mid.b * factor,
                          a: start.a * invFact + mid.a * factor)
            result.append(rgb)
        }
        for i in 0 ..< span2 {
            let factor = Float(i)/span2f
            let invFact = 1 - factor
            let rgb = Rgb(r: mid.r * invFact + end.r * factor,
                          g: mid.g * invFact + end.g * factor,
                          b: mid.b * invFact + end.b * factor,
                          a: mid.a * invFact + end.a * factor)
            result.append(rgb)
        }
        if log { logResult() }
        return result

        func logResult() {
            var script = "ramp[0…\(span-1)] ⟹ "
            for i in 0 ..< result.count {
                if i%(span/2) == 0 { script += "\n" }
                if i%(span/8) == 0 { script += "\(i):\(result[i].script()) "}
            }
            print (script)
        }
    }
    static func makeHardRamp(_ span: Int, _ mid: Rgb) -> [Rgb]  {
        var result = [Rgb]()
        for _ in 0 ..< span {
            result.append(mid)
        }
        return result
    }
}

