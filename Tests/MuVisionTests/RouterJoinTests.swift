import XCTest
@testable import MuVision

/// RouterNode.joined: a masked source's front and back draw as one layer only
/// when both are in this pass and no visible route composites between them
final class RouterJoinTests: XCTestCase {

    typealias U = RouterNode.Uniforms
    typealias S = RouterNode.SourceUniform

    /// front path/z/fade, back path/z/fade; mask and texture on
    func source(_ fx: Float, _ fy: Float, _ ff: Float,
                _ bx: Float, _ by: Float, _ bf: Float,
                mask: Bool = true, tex: Bool = true) -> S {
        S(route: SIMD4(fx, fy, bx, by), fade: SIMD4(ff, mask ? 1 : 0, tex ? 1 : 0, bf))
    }
    /// pipe.flo.h defaults: draw front empty at 2, pal canvas on pal at 1,
    /// camera off, album front raw at 4, back raw at 3, both sliders at 1
    func uniforms(pass: Float = 1) -> U {
        var u = U()
        u.pass.x = pass
        u.draw = source(0, 2, 0, 2, 1, 1)
        u.camera = source(0, 6, 0, 0, 5, 0, mask: false, tex: false)
        u.album = source(1, 4, 1, 1, 3, 1)
        return u
    }

    func testAlbumF1B1Joins() {
        XCTAssertTrue(RouterNode.joined(uniforms()).album)
        XCTAssertFalse(RouterNode.joined(uniforms()).camera)
    }
    func testPartialSlidersStillJoin() {
        var u = uniforms()
        u.album.fade.x = 0.4
        XCTAssertTrue(RouterNode.joined(u).album)
    }
    func testNoMaskKeepsTwoLanes() {
        var u = uniforms()
        u.album.fade.y = 0
        XCTAssertFalse(RouterNode.joined(u).album)
    }
    func testSplitPathsKeepTwoLanes() {
        var u = uniforms()
        u.album.route.z = 2 // back to the cell rule, front raw
        XCTAssertFalse(RouterNode.joined(u).album)
        XCTAssertFalse(RouterNode.joined(uniforms(pass: 2)).album)
    }
    func testFeedPassJoinsCellLanes() {
        var u = uniforms(pass: 2)
        u.album.route.x = 2
        u.album.route.z = 2
        XCTAssertTrue(RouterNode.joined(u).album)
    }
    /// the outputs are bits: a path on both, raw + pal, is in either pass
    func testBothJoinsInEachPass() {
        for pass: Float in [1, 2] {
            var u = uniforms(pass: pass)
            u.album.route.x = 3
            u.album.route.z = 3
            XCTAssertTrue(RouterNode.joined(u).album, "pass \(pass)")
            u.album.route.z = pass == 1 ? 2 : 1 // the back lane in the other pass only
            XCTAssertFalse(RouterNode.joined(u).album, "pass \(pass)")
        }
        XCTAssertTrue(RouterNode.routed(3, 1))
        XCTAssertTrue(RouterNode.routed(3, 2))
        XCTAssertFalse(RouterNode.routed(2, 1))
        XCTAssertFalse(RouterNode.routed(4, 3), "SD-Turbo is neither raw nor pal")
        XCTAssertFalse(RouterNode.routed(0, 3))
    }
    /// a join is the mask's two halves drawn as one: a path on F+B is the
    /// frame unmasked by itself, and two paths on one half are not a whole
    func testOnlyTheTwoHalvesJoin() {
        var u = uniforms()
        XCTAssertEqual(u.album.part, SIMD4(1, 2, 0, 0), "path a on F, path b on B")
        u.album.part = SIMD4(2, 1, 0, 0) // the halves the other way round
        XCTAssertTrue(RouterNode.joined(u).album)
        u.album.part = SIMD4(3, 2, 0, 0)
        XCTAssertFalse(RouterNode.joined(u).album, "F+B on path a")
        u.album.part = SIMD4(1, 3, 0, 0)
        XCTAssertFalse(RouterNode.joined(u).album, "F+B on path b")
        u.album.part = SIMD4(1, 1, 0, 0)
        XCTAssertFalse(RouterNode.joined(u).album, "both on F")
    }
    func testCameraBetweenKeepsSeparation() {
        var u = uniforms()
        u.album.route.y = 5 // front 5, back 3
        u.camera = source(1, 4, 1, 0, 6, 0, mask: false)
        XCTAssertFalse(RouterNode.joined(u).album)
        u.camera.fade.x = 0 // invisible between: no route to keep apart
        XCTAssertTrue(RouterNode.joined(u).album)
    }
    func testDrawStrokesAtFrontZSitBetween() {
        var u = uniforms()
        u.draw.route.x = 1 // strokes raw at z 4, composited before album front at z 4
        u.draw.route.y = 4
        u.draw.fade.x = 1
        XCTAssertFalse(RouterNode.joined(u).album)
        u.draw.route.y = 5 // above both lanes
        XCTAssertTrue(RouterNode.joined(u).album)
    }
    func testFrontBelowBack() {
        var u = uniforms()
        u.album.route.y = 3
        u.album.route.w = 4
        XCTAssertTrue(RouterNode.joined(u).album)
        u.camera = source(1, 4, 1, 0, 6, 0, mask: false) // camera front at 4 precedes album back at 4
        XCTAssertFalse(RouterNode.joined(u).album)
    }
    func testSameZJoinsPastEarlierSource() {
        var u = uniforms()
        u.album.route.y = 4
        u.album.route.w = 4
        u.camera = source(0, 6, 0, 1, 4, 1, mask: false) // camera back at 4, before the album
        XCTAssertTrue(RouterNode.joined(u).album)
    }
    func testCameraJoins() {
        var u = uniforms()
        u.camera = source(1, 6, 1, 1, 5, 1)
        XCTAssertTrue(RouterNode.joined(u).camera)
        XCTAssertTrue(RouterNode.joined(u).album)
    }
}
