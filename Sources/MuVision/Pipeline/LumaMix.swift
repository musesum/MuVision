import Foundation

/// the false disk's mix of real (R) and false (F) color, after the OG luma key:
/// two whole layers -- R every real color route (strokes, camera, album on Raw)
/// in its own z order, F the false canvas -- each luma keyed from its white (W)
/// or black (B) end, which only sets its opacity, the first over the second,
/// both over the black backdrop. The disk point is canvas.luma x y (y up, 0.5 0.5
/// the centre); its angle alone places the mix. Clockwise from 9 o'clock, n
/// the key curve's depth (canvas.lumaCurve), which the thumb's distance from
/// the centre used to set as (1 − r) / 2:
///
///      9…12  (F B 1…n) over (R B 1…n)   9 o'clock: F full
///     12…3   (R W n…1) over (F W n…1)
///      3…6   (R B 1…n) over (F B 1…n)   3 o'clock: R over F unkeyed, as before
///      6…9   (F B n…1) over (R B n…1)
///
/// F on top, 6…12, keys from black on both sides of 9, so real comes through
/// a dark false canvas's background either side of it; W keys 12…3 alone
///
/// A level is the part of its layer's luma range the key keeps, from the far
/// end: 1 keeps all, 0 none. The key is the OG luma key's cut at that level,
/// whites going first on W, blacks on B, its edge a Gaussian spread
/// (canvas.lumaCurve) held to the old edge's band either side of the cut, so
/// past it the key is whole or gone as before: breadth 0 is the old key's
/// own 1/16 wide edge, to within 0.0102, and each quarter of breadth doubles
/// it. Depth 0 and breadth 0, the script defaults, are the old key with the
/// thumb on the rim; depth (1 − r) / 2 is the old key at distance r.
/// The kernel side is `lumaKeep` in pipe.router.metal; RouterNode passes it on
public struct LumaMix: Equatable, Sendable {

    public var realOnTop : Bool  // R over F, else F over R
    public var black     : Bool  // both keys start at the black end, else the white
    public var realLevel : Float // R's key level
    public var falseLevel: Float // F's key level
    public var band      : Float // the cut's edge, half its width over the luma range

    /// canvas.lumaCurve's script defaults: the old key on the rim, n 0, and its edge
    public static let defaultDepth = 0.0
    public static let defaultBreadth = 0.0

    /// the old key's edge: a smoothstep 1/32 either side of the cut
    public static let oldBand: Float = 1.0 / 32
    /// σ of the Gaussian, held to the band, that best fits that smoothstep,
    /// per half width: the two differ by 0.0102 at most, at any width
    public static let sigmaPerBand: Float = 0.52773
    /// breadth 0…1 → the edge's half width, an octave every quarter: the old
    /// 1/32 at 0, 1/8 at 0.5, half the luma range at 1
    public static func band(breadth: Double) -> Float {
        oldBand * Float(pow(16, min(1, max(0, breadth))))
    }
    /// the edge's Gaussian σ
    public var sigma: Float { band * Self.sigmaPerBand }

    /// R over F with nothing keyed: the composite before the mix
    public static let identity = LumaMix(realOnTop: true, black: false, realLevel: 1, falseLevel: 1)

    public init(realOnTop: Bool, black: Bool, realLevel: Float, falseLevel: Float,
                band: Float = LumaMix.band(breadth: LumaMix.defaultBreadth)) {
        self.realOnTop = realOnTop
        self.black = black
        self.realLevel = realLevel
        self.falseLevel = falseLevel
        self.band = band
    }

    /// the disk point, x y 0…1 with y up, and canvas.lumaCurve's depth and breadth
    public init(x: Double, y: Double,
                depth: Double = LumaMix.defaultDepth,
                breadth: Double = LumaMix.defaultBreadth) {
        let dx = x - 0.5, dy = y - 0.5
        let n = min(1, max(0, depth))
        let s = Self.band(breadth: breadth)
        var hour = atan2(dx, dy) / (2 * .pi) * 12 // 0 at 12 o'clock, clockwise
        if hour < 0 { hour += 12 }
        let quarter = min(3, Int(hour / 3))       // 0: 12…3, 1: 3…6, 2: 6…9, 3: 9…12
        let t = hour / 3 - Double(quarter)
        func lerp(_ a: Double, _ b: Double) -> Float { Float(a + (b - a) * t) }
        switch quarter {
        case 0:  self.init(realOnTop: true,  black: false, realLevel: lerp(n, 1), falseLevel: lerp(n, 1), band: s)
        case 1:  self.init(realOnTop: true,  black: true,  realLevel: lerp(1, n), falseLevel: lerp(1, n), band: s)
        case 2:  self.init(realOnTop: false, black: true,  realLevel: lerp(n, 1), falseLevel: lerp(n, 1), band: s)
        default: self.init(realOnTop: false, black: true,  realLevel: lerp(1, n), falseLevel: lerp(1, n), band: s)
        }
    }

    /// looks as before the mix: R over F, neither keyed
    public var isIdentity: Bool { realOnTop && realLevel >= 1 && falseLevel >= 1 }

    /// the part of a layer the key keeps at `luma`: whole below the cut's
    /// band, gone above it, and across it 1 − the Gaussian's cumulative held
    /// to the band, rescaled to run 0…1 over it. u the luma from the far end
    /// (luma on W, 1 − luma on B), c the cut, `level` of the way up with the
    /// band either side. The kernel's lumaKeep, for the tests
    public func keep(luma: Float, level: Float) -> Float {
        guard level < 1 else { return 1 }
        let l = min(1, max(0, luma))
        let u = black ? 1 - l : l
        let c = level * (1 + 2 * band) - band
        let x = (u - c) / max(band, 1e-4) // −1…1 across the edge
        if x <= -1 { return 1 }
        if x >= 1 { return 0 }
        func phi(_ z: Float) -> Float { 0.5 * (1 + erf(z / Float(2).squareRoot())) }
        let a = 1 / Self.sigmaPerBand
        let lo = phi(-a)
        return 1 - (phi(x * a) - lo) / (1 - 2 * lo)
    }

    /// the two entries top first, as the disk's table writes them: "F", "W", level
    public var entries: [(layer: String, key: String, level: Float)] {
        let key = black ? "B" : "W"
        let real = (layer: "R", key: key, level: realLevel)
        let fals = (layer: "F", key: key, level: falseLevel)
        return realOnTop ? [real, fals] : [fals, real]
    }
}
