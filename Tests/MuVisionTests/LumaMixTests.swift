import XCTest
@testable import MuVision

/// LumaMix: the false disk point → which layer is on top, the key end, and each
/// layer's key level; RouterNode.lumaUniform hands it to the kernel
final class LumaMixTests: XCTestCase {

    /// the disk point at `hour` o'clock and radius `r`, y up
    func mix(_ hour: Double, _ r: Double) -> LumaMix {
        let a = hour / 12 * 2 * .pi
        return LumaMix(x: 0.5 + r / 2 * sin(a), y: 0.5 + r / 2 * cos(a))
    }
    func assertMix(_ m: LumaMix, realOnTop: Bool, black: Bool, real: Float, fals: Float,
                   accuracy: Float = 1e-5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(m.realOnTop, realOnTop, "realOnTop", file: file, line: line)
        XCTAssertEqual(m.black, black, "black", file: file, line: line)
        XCTAssertEqual(m.realLevel, real, accuracy: accuracy, "real level", file: file, line: line)
        XCTAssertEqual(m.falseLevel, fals, accuracy: accuracy, "false level", file: file, line: line)
    }

    func testDefaultIsIdentity() {
        let m = LumaMix(x: 1, y: 0.5) // canvas.luma default, the right rim
        XCTAssertEqual(m.realLevel, 1)
        XCTAssertEqual(m.falseLevel, 1)
        XCTAssertTrue(m.realOnTop)
        XCTAssertTrue(m.isIdentity)
        XCTAssertTrue(LumaMix(x: 0.75, y: 0.5).isIdentity, "3 o'clock at any radius")
    }
    func testClockPoints() {
        // exact points: sin and cos land a hair either side of 9, 12 and 6
        assertMix(LumaMix(x: 0, y: 0.5), realOnTop: false, black: true, real: 1, fals: 1) // left is full F
        assertMix(LumaMix(x: 0.5, y: 1), realOnTop: true,  black: false, real: 0, fals: 0) // rim n = 0
        assertMix(LumaMix(x: 0.5, y: 0), realOnTop: false, black: true,  real: 0, fals: 0)
        assertMix(mix(1.5, 1),  realOnTop: true,  black: false, real: 0.5, fals: 0.5) // 12…3 n…1
        assertMix(mix(4.5, 1),  realOnTop: true,  black: true,  real: 0.5, fals: 0.5) // 3…6 1…n
        assertMix(mix(7.5, 1),  realOnTop: false, black: true,  real: 0.5, fals: 0.5) // 6…9 n…1
        assertMix(mix(10.5, 0.5), realOnTop: false, black: true, real: 0.5, fals: 0.5) // any distance
        assertMix(LumaMix(x: 0.5, y: 0.5), realOnTop: true, black: false, real: 0, fals: 0) // centre: 12
    }
    func testNineAndThreeJoin() {
        // either side of 9 o'clock F is on top at full level, keyed from black
        // on both sides: no switch of key end at 9
        assertMix(mix(8.999, 1), realOnTop: false, black: true, real: 1, fals: 1, accuracy: 1e-3)
        assertMix(mix(9.001, 1), realOnTop: false, black: true, real: 1, fals: 1, accuracy: 1e-3)
        // either side of 3 o'clock R over F unkeyed
        assertMix(mix(2.999, 1), realOnTop: true, black: false, real: 1, fals: 1, accuracy: 1e-3)
        assertMix(mix(3.001, 1), realOnTop: true, black: true, real: 1, fals: 1, accuracy: 1e-3)
    }
    func testTwelveAndSixJoin() {
        // at the rim both layers are keyed to 0 either side of 12 and 6
        for m in [mix(11.999, 1), mix(0.001, 1), mix(5.999, 1), mix(6.001, 1)] {
            XCTAssertEqual(m.realLevel, 0, accuracy: 1e-3)
            XCTAssertEqual(m.falseLevel, 0, accuracy: 1e-3)
        }
    }
    func testEntriesTopFirst() {
        let left = mix(10.5, 1).entries
        XCTAssertEqual(left.map { $0.layer + $0.key }, ["FB", "RB"])
        let top = mix(1.5, 1).entries
        XCTAssertEqual(top.map { $0.layer + $0.key }, ["RW", "FW"], "W keys 12…3 alone")
        let low = mix(4.5, 1).entries
        XCTAssertEqual(low.map { $0.layer + $0.key }, ["RB", "FB"])
    }

    /// the old disk, before the curve: n = (1 − r) / 2, levels n…1 by quarter
    func oldLevels(_ x: Double, _ y: Double) -> (real: Float, fals: Float, realOnTop: Bool, black: Bool) {
        let dx = x - 0.5, dy = y - 0.5
        let n = (1 - min(1, 2 * hypot(dx, dy))) / 2
        var hour = atan2(dx, dy) / (2 * .pi) * 12
        if hour < 0 { hour += 12 }
        let quarter = min(3, Int(hour / 3))
        let t = hour / 3 - Double(quarter)
        let rising = quarter == 0 || quarter == 2
        let level = Float(rising ? n + (1 - n) * t : 1 + (n - 1) * t)
        return (level, level, quarter < 2, quarter != 0) // key ends as the table now has them: B but 12…3
    }
    /// depth stands in for the old thumb distance: depth (1 − r) / 2 is the
    /// old disk at every point, the defaults are it on the rim
    func testDepthEmulatesTheOldDisk() {
        var g = SystemRandomNumberGenerator()
        for _ in 0 ..< 2000 {
            let x = Double.random(in: 0 ... 1, using: &g), y = Double.random(in: 0 ... 1, using: &g)
            let r = min(1, 2 * hypot(x - 0.5, y - 0.5))
            let m = LumaMix(x: x, y: y, depth: (1 - r) / 2)
            let o = oldLevels(x, y)
            XCTAssertEqual(m.realLevel, o.real, accuracy: 1e-6, "\(x) \(y)")
            XCTAssertEqual(m.falseLevel, o.fals, accuracy: 1e-6)
            XCTAssertEqual(m.realOnTop, o.realOnTop)
            XCTAssertEqual(m.black, o.black)
            XCTAssertEqual(m.band, LumaMix.oldBand)
            // the rim at the defaults
            let a = atan2(y - 0.5, x - 0.5)
            let rx = 0.5 + cos(a) / 2, ry = 0.5 + sin(a) / 2
            XCTAssertEqual(LumaMix(x: rx, y: ry).realLevel, oldLevels(rx, ry).real, accuracy: 1e-5)
        }
        XCTAssertEqual(LumaMix.defaultDepth, 0)
        XCTAssertEqual(LumaMix.defaultBreadth, 0)
    }
    /// depth is n, whatever the thumb's distance from the centre
    func testDepthIsN() {
        for depth in [0.0, 0.3, 1.0] {
            for y in [1.0, 0.75, 0.55] { // 12 o'clock at the rim, half way, near the centre
                XCTAssertEqual(LumaMix(x: 0.5, y: y, depth: depth).realLevel, Float(depth), accuracy: 1e-6)
            }
        }
        XCTAssertEqual(LumaMix(x: 0.5, y: 1, depth: 2).realLevel, 1, "clamped")
        XCTAssertTrue(LumaMix(x: 0.5, y: 1, depth: 1).isIdentity, "12…3 with nothing keyed is R over F")
        XCTAssertFalse(LumaMix(x: 0.2, y: 0.7, depth: 1).isIdentity, "9…12 keeps F over R")
    }
    /// breadth → the cut edge's half width, an octave every quarter from the
    /// old key's 1/32; σ the Gaussian's that fits that edge
    func testBreadthBands() {
        XCTAssertEqual(LumaMix.band(breadth: 0), 1.0 / 32, accuracy: 1e-7)
        XCTAssertEqual(LumaMix.band(breadth: 0.25), 1.0 / 16, accuracy: 1e-7)
        XCTAssertEqual(LumaMix.band(breadth: 0.5), 1.0 / 8, accuracy: 1e-7)
        XCTAssertEqual(LumaMix.band(breadth: 1), 0.5, accuracy: 1e-7)
        XCTAssertEqual(LumaMix.band(breadth: -1), 1.0 / 32, accuracy: 1e-7, "clamped")
        XCTAssertEqual(LumaMix.identity.band, LumaMix.oldBand, "the script default is the old edge")
        XCTAssertEqual(LumaMix(x: 0.2, y: 0.3, breadth: 0.5).sigma, 0.125 * 0.52773, accuracy: 1e-7)
    }

    /// the key before the curve: 1 − smoothstep(c − m, c + m, u), m 1/32,
    /// c = level (1 + 2m) − m, u the luma from the far end
    func oldKeep(_ luma: Float, _ level: Float, black: Bool) -> Float {
        guard level < 1 else { return 1 }
        let m: Float = 1.0 / 32
        let u = black ? 1 - luma : luma
        let c = level * (1 + 2 * m) - m
        let t = min(1, max(0, (u - (c - m)) / (2 * m)))
        return 1 - t * t * (3 - 2 * t)
    }
    /// breadth 0 is the old key: the same cut at every level, its edge within
    /// 0.0102 of the old smoothstep, the same everywhere off the edge
    func testBreadthZeroIsTheOldKey() {
        var worst: Float = 0
        for black in [false, true] {
            var m = LumaMix(x: 0.5, y: 1, breadth: 0)
            m.black = black
            for level in stride(from: Float(0), through: 1, by: 0.05) {
                for luma in stride(from: Float(0), through: 1, by: 1.0 / 512) {
                    let d = abs(m.keep(luma: luma, level: level) - oldKeep(luma, level, black: black))
                    worst = max(worst, d)
                }
            }
        }
        XCTAssertLessThan(worst, 0.0105)
        XCTAssertGreaterThan(worst, 0.001, "a Gaussian, not the smoothstep itself")
    }
    /// the cut: level of the range kept below it, the edge's Gaussian around
    /// it; black keys mirror white ones; wider breadth, softer edge
    func testGaussianEdge() {
        let w = LumaMix(realOnTop: true, black: false, realLevel: 0.5, falseLevel: 1, band: 0.125)
        XCTAssertEqual(w.keep(luma: 0.5, level: 0.5), 0.5, accuracy: 1e-6, "the cut at mid level")
        XCTAssertEqual(w.keep(luma: 0.3, level: 1), 1)
        XCTAssertEqual(w.keep(luma: 0, level: 0), 0, "level 0 keeps none")
        XCTAssertEqual(w.keep(luma: 1, level: 0.999), oldKeep(1, 0.999, black: false), accuracy: 0.0105,
                       "no jump short of level 1")
        XCTAssertGreaterThan(w.keep(luma: 0.2, level: 0.5), 0.99)
        XCTAssertLessThan(w.keep(luma: 0.8, level: 0.5), 0.01)
        var b = w
        b.black = true
        for l in stride(from: Float(0), through: 1, by: 0.125) {
            XCTAssertEqual(b.keep(luma: l, level: 0.3), w.keep(luma: 1 - l, level: 0.3), accuracy: 1e-6)
        }
        // monotone: the further past the cut the less kept
        var last: Float = 2
        for l in stride(from: Float(0), through: 1, by: 0.0625) {
            let k = w.keep(luma: l, level: 0.4)
            XCTAssertLessThanOrEqual(k, last)
            last = k
        }
        // a wider edge keeps more just past the cut
        let soft = LumaMix(realOnTop: true, black: false, realLevel: 0.5, falseLevel: 1, band: 0.5)
        XCTAssertGreaterThan(soft.keep(luma: 0.6, level: 0.5), w.keep(luma: 0.6, level: 0.5))
    }

    /// the kernel's view: real level, false level, black key, 1 real on top or 2 false
    func testLumaUniform() {
        XCTAssertEqual(RouterNode.lumaUniform(.identity), SIMD4(1, 1, 0, 1))
        let low = RouterNode.lumaUniform(mix(7.5, 1)) // 6…9: F over R, black key
        XCTAssertEqual(low.x, 0.5, accuracy: 1e-5)
        XCTAssertEqual(low.y, 0.5, accuracy: 1e-5)
        XCTAssertEqual(low.z, 1)
        XCTAssertEqual(low.w, 2)
        XCTAssertEqual(RouterNode.curveUniform(LumaMix(x: 0.2, y: 0.3, breadth: 1)), SIMD4(0.5, 0, 0, 0))
    }
}
