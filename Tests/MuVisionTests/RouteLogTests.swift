import XCTest
import MuFlo
@testable import MuVision

/// RouterNode.routeLine and RouteLog: the route as the router pass reads it,
/// in the Layers leaf's notation, logged once a change has settled and led
/// by what changed
final class RouteLogTests: XCTestCase {

    typealias R = RouterNode.RouteSource
    typealias Log = RouterNode.RouteLog

    /// pipe.flo.h defaults: draw F0 B2 at 2/1, camera off at 6/5, album F1 B1 at 4/3
    func sources() -> [R] {
        [R(code: "D", route: SIMD4(0, 2, 2, 1), lane: SIMD2(0, 1)),
         R(code: "C", route: SIMD4(0, 6, 0, 5), lane: SIMD2(0, 0)),
         R(code: "A", route: SIMD4(1, 4, 1, 3), lane: SIMD2(1, 1))]
    }
    static let defaultLine = "DF0B2,CF0B0,AF1B1 · order C,A,D · opacity DF 0.00 DB 1.00 CF 0.00 CB 0.00 AF 1.00 AB 1.00"

    func testRouteLine() {
        XCTAssertEqual(RouterNode.routeLine(sources()), Self.defaultLine)
    }
    /// setRows puts the top row at z 5/6: album on top, then camera, then draw
    func testRouteLineOrderFollowsZ() {
        var s = sources()
        s[2].route.y = 6; s[2].route.w = 5
        s[1].route.y = 4; s[1].route.w = 3
        XCTAssertTrue(RouterNode.routeLine(s).contains("· order A,C,D ·"))
    }
    func testRouteLineOpacity() {
        var s = sources()
        s[1].lane.x = 0.375
        XCTAssertTrue(RouterNode.routeLine(s).hasSuffix("CF 0.38 CB 0.00 AF 1.00 AB 1.00"))
    }
    /// the opacity is the slider's own; a master fade shows after, only when not 1
    func testRouteLineFade() {
        var s = sources()
        s[1].lane.x = 0.4
        s[1].master = 0.5
        XCTAssertTrue(RouterNode.routeLine(s).hasSuffix("CF 0.40 CB 0.00 AF 1.00 AB 1.00 · fade C 0.50"))
    }

    // MARK: - what changed

    func change(_ edit: (inout [R]) -> ()) -> String {
        var s = sources()
        edit(&s)
        return RouterNode.routeChange(RouterNode.routeFields(sources()), RouterNode.routeFields(s))
    }
    func testChangeRadio() {
        XCTAssertEqual(change { $0[1].route.x = 3 }, "CF 0→3")
    }
    func testChangeOrder() {
        XCTAssertEqual(change {
            $0[2].route.y = 6; $0[2].route.w = 5
            $0[1].route.y = 4; $0[1].route.w = 3
        }, "order C,A,D→A,C,D")
    }
    func testChangeOpacity() {
        XCTAssertEqual(change { $0[2].lane.y = 0.4 }, "AB opacity 1.00→0.40")
    }
    /// the master moves alone: the sliders read as they were
    func testChangeFade() {
        XCTAssertEqual(change { $0[1].master = 0.5 }, "C fade 1.00→0.50")
    }
    /// several at once read in the leaf's order: radios, rows, sliders, fades
    func testChangeSeveral() {
        XCTAssertEqual(change { $0[2].lane.y = 0.4; $0[1].route.x = 3; $0[0].route.z = 1; $0[0].master = 0 },
                       "DB 2→1, CF 0→3, AB opacity 1.00→0.40, D fade 1.00→0.00")
    }
    /// a path carrying another part than its own half reads after the fades,
    /// and a change of part reads as the leaf's letters
    func testRouteLinePart() {
        var s = sources()
        s[1].part = SIMD2(3, 2)
        XCTAssertTrue(RouterNode.routeLine(s).hasSuffix("AF 1.00 AB 1.00 · part CF F+B"))
        s[2].part = SIMD2(1, 1)
        s[1].master = 0.5
        XCTAssertTrue(RouterNode.routeLine(s).hasSuffix(" · fade C 0.50 · part CF F+B AB F"))
        XCTAssertEqual(change { $0[1].part = SIMD2(3, 2) }, "CF part F→F+B")
        XCTAssertEqual(change { $0[2].part = SIMD2(1, 3) }, "AB part B→F+B")
    }
    /// under a hundredth a slider hasn't moved as the log reads it
    func testChangeBelowAHundredthIsNone() {
        XCTAssertEqual(change { $0[2].lane.y = 0.999 }, "")
    }
    func testFirstRouteHasNoChange() {
        XCTAssertEqual(RouterNode.routeChange([], RouterNode.routeFields(sources())), "")
    }

    // MARK: - what the source reads

    /// the kernel draws slider × master; the log keeps the slider and the master apart
    func testSourceKeepsSliderAndMasterApart() {
        let root = Flo("√")
        XCTAssertTrue(FloParse().parseRoot(root, """
            router {
                draw {
                    tex   (texture)
                    front (x 0…7=1, y 1…6=2, z 0…1=0.4)
                    back  (x 0…7=2, y 1…6=1, z 0…1=1)
                    fade  (x 0…1=0.5)
                }
            }
            """))
        let draw = RouterNode.Source(root.findPath("router"), "draw", mask: false)
        let u = draw.uniform()
        XCTAssertEqual(u.fade.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(u.fade.w, 0.5, accuracy: 1e-6)
        let r = draw.routeSource("D", u)
        XCTAssertEqual(r.route, SIMD4(1, 2, 2, 1))
        XCTAssertEqual(r.part, SIMD2(1, 2), "draw's lanes carry no w: each keeps its half")
        XCTAssertEqual(r.lane, SIMD2(0.4, 1))
        XCTAssertEqual(r.master, 0.5)
        XCTAssertEqual(RouterNode.routeLine([r]), "DF1B2 · order D · opacity DF 0.40 DB 1.00 · fade D 0.50")
    }

    // MARK: - when it logs

    /// the frames the log speaks on, and what it says
    func run(_ log: inout Log, _ s: [R], frames: Int) -> [(frame: Int, line: String)] {
        (1...frames).compactMap { i in log.frame(s).map { (i, $0) } }
    }

    func testFirstRouteLogsWholeOnceSettled() {
        var log = Log()
        let said = run(&log, sources(), frames: 40)
        XCTAssertEqual(said.map(\.frame), [Log.settle])
        XCTAssertEqual(said.first?.line, Self.defaultLine)
    }
    func testChangeLeadsTheLine() {
        var log = Log()
        _ = run(&log, sources(), frames: 20)
        var s = sources()
        s[1].route.x = 3
        let said = run(&log, s, frames: 20)
        XCTAssertEqual(said.map(\.frame), [Log.settle])
        XCTAssertEqual(said.first?.line, "CF 0→3 · " + RouterNode.routeLine(s))
    }
    /// a drag changes the route every frame: one line where it stops,
    /// from where it started
    func testDragLogsFromStartToStop() {
        var log = Log()
        _ = run(&log, sources(), frames: 20)
        var s = sources()
        for i in 0..<30 {
            s[2].lane.y = 1 - Float(i) / 50
            XCTAssertNil(log.frame(s))
        }
        s[2].lane.y = 0.4
        let said = run(&log, s, frames: 20)
        XCTAssertEqual(said.map(\.frame), [Log.settle])
        XCTAssertEqual(said.first?.line.hasPrefix("AB opacity 1.00→0.40 · "), true)
    }
    /// a change shorter than settle, back to the logged route, logs nothing
    func testFlickerLogsNothing() {
        var log = Log()
        _ = run(&log, sources(), frames: 20)
        var s = sources()
        s[1].route.x = 3
        XCTAssertTrue(run(&log, s, frames: Log.settle - 1).isEmpty)
        XCTAssertTrue(run(&log, sources(), frames: 20).isEmpty)
        XCTAssertEqual(log.logged, RouterNode.routeFields(sources()))
    }
}
