import Foundation
import MuFlo

public class ColorFlo {

    nonisolated(unsafe) public static weak var current: ColorFlo? // menu palette views read the live mix

    var cycle˚: Flo? ; var cycleOfs = Float(0) ; var cycleRate = Float(0) // x offset 0…1, y rotations per second
    var cycleTime = Float(0)               // integrated rotation from cycleRate
    var cycleLast = Date().timeIntervalSince1970
    public private(set) var lastRgbs = Rgbs()  // xfade blend after ripples, rotation
    public private(set) var lastRgbs0 = Rgbs() // pal0 after ripples, rotation, before blend
    public private(set) var lastRgbs1 = Rgbs() // pal1 likewise
    var pal0˚: Flo?  ; var pal0 = "rgbK"    // Red Green Blue with blacK interstitials
    var pal1˚: Flo?  ; var pal1 = "wKZ"     // white ramps from black, zeno fractal
    var xfade˚: Flo? ; var xfade = Float(0) // 0 = pal0, 1 = pal1
    var ofs0˚: Flo?  ; var ofs0 = Float(0)  // pal0 start offset
    var ofs1˚: Flo?  ; var ofs1 = Float(0)  // pal1 start offset

    var colors = [ColorRender]() // the two palettes
    var changed = true

    /// a preset load fading in: the colors it replaces, blended out over `span`
    struct PalFade { let from: [Rgb]; let start: TimeInterval; let span: Float }
    var fades: [PalFade?] = [nil, nil]

    var mix: UnsafeMutablePointer<UInt32>?
    var mixSize = 0

    var ripples: Ripples

    public init(_ pipeNode˚: Flo,
                _ ripples: Ripples) {
        self.colors = [ColorRender(pal0), ColorRender(pal1)]
        self.ripples = ripples
        ColorFlo.current = self
        let root˚ = pipeNode˚.getRoot()
        if let color = root˚.findPath("sky.color") {

            pal0˚ = color.bind("pal0") { flo,_ in
                self.pal0 = flo.string
                self.colors[0] = ColorRender(flo.string)
                self.changed = true
            }
            pal0˚?.activate([], Visitor(0, .model))

            pal1˚ = color.bind("pal1") { flo,_ in
                self.pal1 = flo.string
                self.colors[1] = ColorRender(flo.string)
                self.changed = true
            }
            pal1˚?.activate([], Visitor(0, .model))

            xfade˚ = color.bind("xfade") { flo,_ in
                self.xfade = flo.float
                self.changed = true
            }
            if let xfade˚ { xfade = xfade˚.float }

            ofs0˚ = color.bind("ofs0") { flo,_ in
                self.ofs0 = flo.float
                self.changed = true
            }
            ofs1˚ = color.bind("ofs1") { flo,_ in
                self.ofs1 = flo.float
                self.changed = true
            }
            if let ofs0˚ { ofs0 = ofs0˚.float }
            if let ofs1˚ { ofs1 = ofs1˚.float }

            cycle˚ = color.bind("cycle") { flo,_ in
                let v = flo.xyz
                self.cycleOfs = v.x
                self.cycleRate = v.y
                self.changed = true
            }
            if let cycle˚ { cycleOfs = cycle˚.xyz.x; cycleRate = cycle˚.xyz.y }
        }
        changed = true
    }
    /// called before the palette string write: the swap that follows becomes
    /// the fade target, and a fade already running blends into the capture
    public func beginFade(_ pal: Int, seconds: Float) {
        guard colors.indices.contains(pal) else { return }
        guard seconds > 0 else { fades[pal] = nil; return }
        var from = colors[pal].rgbs
        blendFade(pal, &from, Date().timeIntervalSince1970)
        fades[pal] = PalFade(from: from, start: Date().timeIntervalSince1970, span: seconds)
    }
    /// mix the fading-out colors over the current ones by elapsed fraction
    private func blendFade(_ pal: Int, _ rgbs: inout Rgbs, _ now: TimeInterval) {
        guard let fade = fades[pal] else { return }
        let f = max(0, Float(now - fade.start) / fade.span)
        if f >= 1 { fades[pal] = nil; return }
        let g = 1 - f
        for i in 0 ..< min(rgbs.count, fade.from.count) {
            let p = fade.from[i]
            let q = rgbs[i]
            rgbs[i] = Rgb(r: p.r * g + q.r * f,
                          g: p.g * g + q.g * f,
                          b: p.b * g + q.b * f,
                          a: p.a * g + q.a * f)
        }
    }

    /// rotate the palette to begin `ofs` of its length in
    func rotate(_ rgbs: inout Rgbs, _ ofs: Float) {
        let count = rgbs.count
        guard count > 0 else { return }
        let shift = ((Int((ofs * Float(count)).rounded()) % count) + count) % count
        if shift == 0 { return }
        rgbs = Array(rgbs[shift...] + rgbs[..<shift])
    }
    deinit {
        mix?.deallocate()
        mix = nil
    }

    public func getPal(_ palSize: Int) -> UnsafeMutablePointer<UInt32>? {

        if true || changed || palSize != mixSize { //...
            changed = false

            // cycle rotation integrated once per frame, shared by both palettes
            let now = Date().timeIntervalSince1970
            let dt = Float(now - cycleLast)
            cycleLast = now
            if cycleRate != 0 {
                cycleTime = (cycleTime + cycleRate * min(dt, 0.1)).truncatingRemainder(dividingBy: 1)
            }
            let cycling = cycleOfs + cycleTime

            var rgbs0 = colors[0].rgbs
            var rgbs1 = colors[1].rgbs
            blendFade(0, &rgbs0, now)
            blendFade(1, &rgbs1, now)
            ripples.update(&rgbs0)
            ripples.update(&rgbs1)
            rotate(&rgbs0, ofs0 + cycling)
            rotate(&rgbs1, ofs1 + cycling)
            lastRgbs0 = rgbs0
            lastRgbs1 = rgbs1

            var rgbs: Rgbs
            if      xfade <= 0 { rgbs = rgbs0 }
            else if xfade >= 1 { rgbs = rgbs1 }
            else {
                rgbs = rgbs0
                let f = xfade
                let g = 1 - f
                for i in 0 ..< min(rgbs0.count, rgbs1.count) {
                    let p = rgbs0[i]
                    let q = rgbs1[i]
                    rgbs[i] = Rgb(r: p.r * g + q.r * f,
                                  g: p.g * g + q.g * f,
                                  b: p.b * g + q.b * f,
                                  a: p.a * g + q.a * f)
                }
            }
            lastRgbs = rgbs

            if mixSize != palSize {
                mixSize = palSize
                mix?.deallocate()
                mix = UnsafeMutablePointer<UInt32>.allocate(capacity: mixSize)
            }
            // convert [Rgb] to [Uint32]
            guard let mixPointer = mix else { return nil }
            let count = min(rgbs.count, mixSize)
            for i in 0 ..< count {
                let rgb = rgbs[i]
                let b8 = UInt32(rgb.b * 255.0)
                let g8 = UInt32(rgb.g * 255.0) << 8
                let r8 = UInt32(rgb.r * 255.0) << 16
                let a8 = UInt32(rgb.a * 255.0) << 24
                let bgra = b8 | g8 | r8 | a8
                mixPointer[i] = bgra
            }
        }
        return mix
    }
}
