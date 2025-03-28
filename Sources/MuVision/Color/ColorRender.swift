import Foundation
import MuFlo 
public struct ColorRender {

    private var rgbDef = [Rgb]() // definition of Rgb ramps
    private var splice = ColorOps.gradient // how to join this color set with its neighbors
    private let black = Rgb(r: 0, g: 0, b: 0)
    private let white = Rgb(r: 1, g: 1, b: 1)
    private var rendered = [Rgb]() // final render of palette with gradient fades

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

    public init(_ script: String) {
        for s in script {
            switch s {
            case "r": rgbDef.append(Hsv(    0, 1, 1).rgb()) // red
            case "o": rgbDef.append(Hsv( 1/12, 1, 1).rgb()) // orange
            case "y": rgbDef.append(Hsv( 2/12, 1, 1).rgb()) // yellow
            case "g": rgbDef.append(Hsv( 4/12, 1, 1).rgb()) // green
            case "b": rgbDef.append(Hsv( 8/12, 1, 1).rgb()) // blue
            case "i": rgbDef.append(Hsv( 9/12, 1, 1).rgb()) // indigo
            case "v": rgbDef.append(Hsv(10/12, 1, 1).rgb()) // violet
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

    public static func fade(from: ColorRender, to: ColorRender, _ factor: Float) -> [Rgb] {

        var ret = [Rgb]()
        let count = min(from.rendered.count, to.rendered.count)
        let factor01 = factor < 0 ? 0 : factor > 1 ? 1 : factor
         let invFact = 1-factor01
        for i in 0 ..< count {
            let fromi = from.rendered[i]
            let toi = to.rendered[i]
            let rgb = Rgb(r: fromi.r * invFact + toi.r * factor01,
                          g: fromi.g * invFact + toi.g * factor01,
                          b: fromi.b * invFact + toi.b * factor01,
                          a: fromi.a * invFact + toi.a * factor01)
            ret.append(rgb)
        }
        return ret
    }

   

    /// render colors into a rgb array
    func renderSub(_ size: Int) -> [Rgb] {

        if size < 1 { return [] }
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
