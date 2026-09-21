import Foundation
import MuFlo 
public struct ColorRender {

    private var rgbDef = [Rgb]() // definition of Rgb ramps
    private var splice = ColorOps.gradient // how to join this color set with its neighbors
    private let black = Rgb(r: 0, g: 0, b: 0)
    private let white = Rgb(r: 1, g: 1, b: 1)
    private var rendered = [Rgb]() // final render of palette with gradient fades
    public var rgbs: [Rgb] { rendered }

    public init (hsvs: [Hsv], _ splice: ColorOps = .gradient) {
        self.splice = splice
        for hsv in hsvs {
            rgbDef.append(hsv.rgb())  // matching rgbs for hsvs
        }
        render(size: 256)
    }
    public init(rgbs: [Rgb], _ splice: ColorOps = .gradient) {
        self.rgbDef = rgbs
        self.splice = splice
        render(size: 256)
    }

    /// letters name ramp colors, capitals and `/` set the splice, `#rrggbb` is a literal color;
    /// no splice letter = hard bands
    public init(_ script: String) {
        splice = []
        let chars = Array(script)
        var i = 0
        while i < chars.count {
            let s = chars[i]
            i += 1
            if s == "#", i + 6 <= chars.count, let rgb = ColorRender.hex(String(chars[i ..< i + 6])) {
                rgbDef.append(rgb)
                i += 6
                continue
            }
            switch s {
            case "r": rgbDef.append(Hsv(    0, 1, 1).rgb()) // red
            case "o": rgbDef.append(Hsv( 1/12, 1, 1).rgb()) // orange
            case "y": rgbDef.append(Hsv( 2/12, 1, 1).rgb()) // yellow
            case "g": rgbDef.append(Hsv( 4/12, 1, 1).rgb()) // green
            case "c": rgbDef.append(Hsv( 6/12, 1, 1).rgb()) // cyan
            case "b": rgbDef.append(Hsv( 8/12, 1, 1).rgb()) // blue
            case "i": rgbDef.append(Hsv( 9/12, 1, 1).rgb()) // indigo
            case "v": rgbDef.append(Hsv(10/12, 1, 1).rgb()) // violet, the same hue as m
            case "m": rgbDef.append(Hsv(10/12, 1, 1).rgb()) // magenta: the picker's circle
            case "k": rgbDef.append(Hsv(    0, 0, 0).rgb()) // black
            case "w": rgbDef.append(Hsv(    0, 0, 1).rgb()) // whitecase
            case "/": splice.insert(.gradient)
            case "K": splice.insert(.black)
            case "W": splice.insert(.white)
            case "Z": splice.insert(.zeno)
            case "F": splice.insert(.flip)
            case " ": break // skip space
            default: PrintLog("⁉️ unknown Color shortcut")
            }
        }
        render(size: 256)
    }

    /// six hex digits → rgb
    public static func hex(_ hex: String) -> Rgb? {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return Rgb(r: Float((v >> 16) & 0xFF) / 255, g: Float((v >> 8) & 0xFF) / 255, b: Float(v & 0xFF) / 255)
    }
    /// rgb → `#rrggbb`
    public static func hex(_ rgb: Rgb) -> String {
        String(format: "#%02x%02x%02x", Int(rgb.r * 255 + 0.5), Int(rgb.g * 255 + 0.5), Int(rgb.b * 255 + 0.5))
    }
    /// a color token: lowercase letter or `#rrggbb`; capitals and `/` are splice letters
    public static func isColor(_ token: String) -> Bool {
        token.hasPrefix("#") || (token.count == 1 && token == token.lowercased() && token != "/" && token != " ")
    }
    /// script split into palette tokens: one letter or one `#rrggbb`
    public static func tokens(_ script: String) -> [String] {
        var out = [String]()
        let chars = Array(script)
        var i = 0
        while i < chars.count {
            if chars[i] == "#", i + 7 <= chars.count { out.append(String(chars[i ..< i + 7])); i += 7 }
            else { out.append(String(chars[i])); i += 1 }
        }
        return out
    }

    /// render colors into a rgb array
    func renderSub(_ size: Int) -> [Rgb] {

        if size < 1 { return [] }
        if rgbDef.isEmpty { return [Rgb](repeating: black, count: size) } // all-splice or empty script
        if size == 1 { return [rgbDef[0]] }

        var result = [Rgb]()

        let count = rgbDef.count
        let increment = size / count
        var remain = size

        for i in 0 ..< count {

            let lefti = (i+count-1) % count  // wrap around to just left of my color
            let righti = (i+1) % count       // to right of my color with wrap around
            let left = rgbDef[lefti]         // to the left of my color
            let mid = rgbDef[i]              // my color
            let right = rgbDef[righti]       // to the right of my color

            let span = (i == count-1 ? remain : increment)
            remain -= span

            if      splice.black    { addRamp(span, black, mid, black) }
            else if splice.white    { addRamp(span, white, mid, white) }
            else if splice.gradient { addRamp(span, left, mid, right) }
            else                    { addHard(span, mid) }
        }
        if splice.zeno { result.append(contentsOf: renderSub((size+1)/2)) }
        return result
        func addRamp(_ span: Int, _ left: Rgb, _ mid: Rgb, _ right: Rgb) {
            result.append(contentsOf: Rgb.makeRamp(span, left, mid, right, /* logging */ false))
        }
        func addHard(_ span: Int, _ mid: Rgb) {
            result.append(contentsOf: Rgb.makeHardRamp(span, mid))
        }
    }

    /// runder color palette from
    mutating func render(size: Int) {

        if splice.zeno {
            // zeno's paradox fractalizes palette,
            // for size=256: 128 + 64 + 32 + ... + 1
            rendered = renderSub(size/2)
            // for size==256, renders 255 items, so top off with fill color
            let fill = splice.white ? white : black
            while rendered.count < size {
                rendered.append(fill)
            }
        } else {
            rendered = renderSub(size)
        }
    }

    func flip(_ rgbs: [Rgb]) -> [Rgb]{

        var ret = [Rgb]()
        for rgb in rgbs.reversed() {
            ret.append(rgb)
        }
        return ret
    }

    func middle(_ p: Hsv, _ q: Hsv) -> Hsv {

        let ret = Hsv((p.hue + q.hue) / 2,
                      (p.sat + q.sat) / 2,
                      (p.val + q.val) / 2)
        return ret
    }

}
