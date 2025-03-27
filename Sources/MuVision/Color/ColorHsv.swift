//  created by musesum on 7/30/19.

import Foundation

public struct Hsv {

    internal var hue: Float // 0...1/ degree instead of radians
    internal var sat: Float // 0...1
    internal var val: Float // 0...1

    init(_ hue: Float, _ sat: Float, _ val: Float) {

        self.hue = hue
        self.sat = sat
        self.val = val
    }
    /// hue: 0..<360
    /// 
    public func rgb() -> Rgb {

        if sat == 0 { return Rgb(r: val, g: val, b: val) }

        let ss = sat   // normalize saturation 0...100 to 0...1
        let vv = val    // normalize value 0...100 to 0...1
        if ss == 0 { return Rgb(r: vv, g: vv, b: vv) }

        let hue6 = hue * 6  // divide hue 0..<360 into 6 sections 0..<6
        let huei = floor(hue6)  // integer part of hue
        let huef = hue6 - huei    // fractional part of hue for gradient
        let fx = vv * (1 - ss ) // fixed component value for section
        let up = vv * (1 - ss * huef ) // component ramp up
        let dn = vv * (1 - ss * ( 1 - huef ) ) // ramp down

        var r = Float.zero
        var g = Float.zero
        var b = Float.zero

        ///    `r   g   b   r`
        ///    ` ╲ ╱ ╲ ╱ ╲ ╱ `
        ///    ` ╱ ╲ ╱ ╲ ╱ ╲ `
        ///    `0 1 2 3 4 5 6`
        switch huei  { // which of 6 sections
        case 0: r = vv; g = dn; b = fx
        case 1: r = up; g = vv; b = fx
        case 2: r = fx; g = vv; b = dn
        case 3: r = fx; g = up; b = vv
        case 4: r = dn; g = fx; b = vv
        case 5: r = vv; g = fx; b = up
        default: break
        }
        return Rgb(r: r, g: g, b: b) // converts normalized floats back to UInt8s
    }
}
