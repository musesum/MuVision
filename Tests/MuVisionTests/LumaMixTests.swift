import XCTest
@testable import MuVision

/// LumaMix: the pal disk point → which layer is on top, the key end, and each
/// layer's key level; RouterNode.lumaUniform hands it to the kernel
final class LumaMixTests: XCTestCase {

    /// the disk point at `hour` o'clock and radius `r`, y up
    func mix(_ hour: Double, _ r: Double, depth: Double = 0) -> LumaMix {
        let a = hour / 12 * 2 * .pi
        return LumaMix(x: 0.5 + r / 2 * sin(a), y: 0.5 + r / 2 * cos(a), depth: depth)
    }
    func assertMix(_ m: LumaMix, realOnTop: Bool, black: Bool, real: Float, pal: Float,
                   accuracy: Float = 1e-5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(m.realOnTop, realOnTop, "realOnTop", file: file, line: line)
        XCTAssertEqual(m.black, black, "black", file: file, line: line)
        XCTAssertEqual(m.realLevel, real, accuracy: accuracy, "real level", file: file, line: line)
        XCTAssertEqual(m.palLevel, pal, accuracy: accuracy, "pal level", file: file, line: line)
    }

    /// the table, clockwise, the first entry over the second, only it keyed:
    ///     09..12: (P B 1..n), (R 1..1)
    ///     12..03: (R B 1..n), (P 1..1)
    ///     03..06: (R W n..1), (P 1..1)
    ///     06..09: (P W n..1), (R 1..1)
    func testDefaultIsIdentity() {
        let m = LumaMix(x: 0.5, y: 1) // canvas.luma default, 12 o'clock on the rim
        XCTAssertEqual(m.realLevel, 1)
        XCTAssertEqual(m.palLevel, 1)
        XCTAssertTrue(m.realOnTop)
        XCTAssertTrue(m.isIdentity)
        XCTAssertTrue(LumaMix(x: 0.5, y: 0.75).isIdentity, "12 o'clock at any radius")
        XCTAssertTrue(LumaMix(x: 0.5, y: 0.5).isIdentity, "the centre counts as 12")
    }
    func testClockPoints() {
        // half way through each quarter, depth 0: the top layer at 0.5, the one under it whole
        assertMix(mix(1.5, 1),  realOnTop: true,  black: true,  real: 0.5, pal: 1)   // 12..03
        assertMix(mix(4.5, 1),  realOnTop: true,  black: false, real: 0.5, pal: 1)   // 03..06
        assertMix(mix(7.5, 1),  realOnTop: false, black: false, real: 1, pal: 0.5)   // 06..09
        assertMix(mix(10.5, 0.5), realOnTop: false, black: true, real: 1, pal: 0.5)  // 09..12, any distance
        // the clock points themselves
        assertMix(LumaMix(x: 1, y: 0.5), realOnTop: true,  black: false, real: 0, pal: 1) // 3: R keyed to n
        assertMix(LumaMix(x: 0.5, y: 0), realOnTop: false, black: false, real: 1, pal: 0) // 6: P keyed to n
        assertMix(LumaMix(x: 0, y: 0.5), realOnTop: false, black: true,  real: 1, pal: 1) // 9: P over R whole
    }
    /// 9 o'clock joins, P over R whole either side; 3 keeps R on top at n,
    /// its key end turning from B to W; 12 and 6 are where the top layer changes
    func testSeams() {
        assertMix(mix(8.999, 1), realOnTop: false, black: false, real: 1, pal: 1, accuracy: 1e-3)
        assertMix(mix(9.001, 1), realOnTop: false, black: true,  real: 1, pal: 1, accuracy: 1e-3)
        for depth in [0.0, 0.4] {
            let before = mix(2.999, 1, depth: depth), after = mix(3.001, 1, depth: depth)
            XCTAssertTrue(before.realOnTop && after.realOnTop)
            XCTAssertEqual(before.realLevel, Float(depth), accuracy: 1e-3)
            XCTAssertEqual(after.realLevel, Float(depth), accuracy: 1e-3)
            XCTAssertTrue(before.black)
            XCTAssertFalse(after.black)
        }
        let left12 = mix(11.999, 1), right12 = mix(0.001, 1)
        XCTAssertFalse(left12.realOnTop)
        XCTAssertEqual(left12.palLevel, 0, accuracy: 1e-3, "P keyed to n just left of 12")
        XCTAssertTrue(right12.realOnTop)
        XCTAssertEqual(right12.realLevel, 1, accuracy: 1e-3, "R over P whole just right of 12")
        let above6 = mix(5.999, 1), below6 = mix(6.001, 1)
        XCTAssertTrue(above6.realOnTop)
        XCTAssertEqual(above6.realLevel, 1, accuracy: 1e-3, "R over P whole just above 6")
        XCTAssertFalse(below6.realOnTop)
        XCTAssertEqual(below6.palLevel, 0, accuracy: 1e-3, "P keyed to n just below 6")
    }
    func testEntriesTopFirst() {
        XCTAssertEqual(mix(10.5, 1).entries.map { $0.layer + $0.key }, ["PB", "R"])
        XCTAssertEqual(mix(1.5, 1).entries.map { $0.layer + $0.key }, ["RB", "P"])
        XCTAssertEqual(mix(4.5, 1).entries.map { $0.layer + $0.key }, ["RW", "P"])
        XCTAssertEqual(mix(7.5, 1).entries.map { $0.layer + $0.key }, ["PW", "R"])
        XCTAssertEqual(mix(7.5, 1).entries.last?.level, 1, "the one under is whole")
    }
    /// depth is n, the keyed layer's level at 3 and 6 o'clock, whatever the
    /// thumb's distance from the centre
    func testDepthIsN() {
        for depth in [0.0, 0.3, 1.0] {
            for r in [1.0, 0.5, 0.1] {
                XCTAssertEqual(LumaMix(x: 0.5 + r / 2, y: 0.5, depth: depth).realLevel, Float(depth), accuracy: 1e-6)
                XCTAssertEqual(LumaMix(x: 0.5, y: 0.5 - r / 2, depth: depth).palLevel, Float(depth), accuracy: 1e-6)
            }
        }
        XCTAssertEqual(LumaMix(x: 1, y: 0.5, depth: 2).realLevel, 1, "clamped")
        XCTAssertTrue(LumaMix(x: 1, y: 0.5, depth: 1).isIdentity, "3 o'clock with nothing keyed is R over P")
        XCTAssertFalse(LumaMix(x: 0.2, y: 0.7, depth: 1).isIdentity, "09..12 keeps P over R")
        XCTAssertEqual(LumaMix.defaultDepth, 0)
        XCTAssertEqual(LumaMix.defaultBreadth, 0)
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
        let w = LumaMix(realOnTop: true, black: false, realLevel: 0.5, palLevel: 1, band: 0.125)
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
        let soft = LumaMix(realOnTop: true, black: false, realLevel: 0.5, palLevel: 1, band: 0.5)
        XCTAssertGreaterThan(soft.keep(luma: 0.6, level: 0.5), w.keep(luma: 0.6, level: 0.5))
    }

    /// the kernel's view: real level, pal level, black key, 1 real on top or 2 pal
    func testLumaUniform() {
        XCTAssertEqual(RouterNode.lumaUniform(.identity), SIMD4(1, 1, 0, 1))
        let low = RouterNode.lumaUniform(mix(7.5, 1)) // 06..09: P over R, white key, R whole
        XCTAssertEqual(low.x, 1, accuracy: 1e-5)
        XCTAssertEqual(low.y, 0.5, accuracy: 1e-5)
        XCTAssertEqual(low.z, 0)
        XCTAssertEqual(low.w, 2)
        XCTAssertEqual(RouterNode.curveUniform(LumaMix(x: 0.2, y: 0.3, breadth: 1)), SIMD4(0.5, 0, 0, 0))
    }
}
