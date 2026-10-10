import XCTest
@testable import MuVision

/// canvas.mix's fade in the router pass, the camera on Raw: pal·(1−x) +
/// camera·x where the camera covers, whichever layer the mix wheel puts on
/// top, the strokes and the album left as they are
final class RouterBlendTests: XCTestCase {

    typealias S = RouterNode.SourceUniform

    /// front outputs and slider, back outputs and slider, under master `m`
    func camera(_ fx: Float, _ ff: Float, _ bx: Float, _ bf: Float,
                master m: Float, tex: Bool = true) -> S {
        S(route: SIMD4(fx, 6, bx, 5), fade: SIMD4(ff * m, 1, tex ? 1 : 0, bf * m))
    }

    /// one route of the real layer at a pixel, one channel
    struct Route {
        var color: Float
        var alpha: Float      // its own slider times its coverage
        var camera = false
    }
    /// the kernel's router pass at a pixel, one channel: the real routes bottom
    /// first into one layer, then the two layers over black. `fade` is
    /// canvas.mix's, as RouterNode.blend hands it on: real on top it rides
    /// the camera's alpha, pal on top it thins the pal over the camera
    func composite(_ routes: [Route], pal: Float, palA: Float = 1,
                   fade: Float, realOnTop: Bool) -> Float {
        var rgb: Float = 0, a: Float = 0, share: Float = 0
        for r in routes {
            let ra = r.camera && realOnTop ? r.alpha * fade : r.alpha
            rgb = r.color * ra + rgb * (1 - ra)
            a = ra + a * (1 - ra)
            share = r.camera ? ra + share * (1 - ra) : share * (1 - ra)
        }
        let real = a > 0 ? rgb / a : 0
        func over(_ under: Float, _ top: Float, _ a: Float) -> Float { under + (top - under) * a }
        if realOnTop { return over(over(0, pal, palA), real, a) }
        let pa = palA * RouterNode.palOverCamera(fade, share: share)
        return over(over(0, real, a), pal, pa)
    }

    func testCameraOnRawIsInReal() {
        XCTAssertTrue(RouterNode.cameraInReal(camera(1, 1, 0, 0, master: 0.5)))
        XCTAssertTrue(RouterNode.cameraInReal(camera(0, 0, 1, 1, master: 0.5)))
        XCTAssertTrue(RouterNode.cameraInReal(camera(3, 1, 0, 0, master: 0.5)), "Both holds Raw")
        XCTAssertFalse(RouterNode.cameraInReal(camera(2, 1, 2, 1, master: 0.5)), "on Pal alone")
        XCTAssertFalse(RouterNode.cameraInReal(camera(0, 1, 0, 1, master: 0.5)), "Empty")
        XCTAssertFalse(RouterNode.cameraInReal(camera(1, 1, 1, 1, master: 0.5, tex: false)), "not running")
    }

    /// real over pal: the fade stays on the camera's own paths
    func testRealOnTopFadesTheCameraPaths() {
        var c = camera(1, 0.8, 1, 0.6, master: 0.25)
        let blend = RouterNode.blend(&c, lane: SIMD2(0.8, 0.6), master: 0.25, realOnTop: true)
        XCTAssertEqual(blend.y, 0, "the pal layer is left alone")
        XCTAssertEqual(c.fade.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(c.fade.w, 0.15, accuracy: 1e-6)
    }

    /// pal over real: the camera's paths keep their sliders, the pal thins
    func testPalOnTopKeepsTheCameraSliders() {
        var c = camera(1, 0.8, 1, 0.6, master: 0.25)
        let blend = RouterNode.blend(&c, lane: SIMD2(0.8, 0.6), master: 0.25, realOnTop: false)
        XCTAssertEqual(blend, SIMD4(0.25, 1, 0, 0))
        XCTAssertEqual(c.fade.x, 0.8, accuracy: 1e-6)
        XCTAssertEqual(c.fade.w, 0.6, accuracy: 1e-6)
    }

    func testPalCameraKeepsItsFade() {
        var c = camera(2, 0.8, 2, 0.6, master: 0.25)
        let blend = RouterNode.blend(&c, lane: SIMD2(0.8, 0.6), master: 0.25, realOnTop: false)
        XCTAssertEqual(blend.y, 0, "the pal layer does not thin")
        XCTAssertEqual(c.fade.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(c.fade.w, 0.15, accuracy: 1e-6)
    }

    func testDefaultUniformFadesNothing() {
        XCTAssertEqual(RouterNode.Uniforms().blend.y, 0)
    }

    /// the whole camera over the whole pal: pal·(1−x) + camera·x either way round
    func testCameraCrossesWithPal() {
        let cam = [Route(color: 0.9, alpha: 1, camera: true)]
        for realOnTop in [true, false] {
            for x: Float in [0, 0.25, 0.5, 0.75, 1] {
                let out = composite(cam, pal: 0.2, fade: x, realOnTop: realOnTop)
                XCTAssertEqual(out, 0.2 * (1 - x) + 0.9 * x, accuracy: 1e-6, "x \(x) realOnTop \(realOnTop)")
            }
        }
    }

    /// a stroke where the camera holds nothing is what it was without the fade
    func testStrokesStayAsTheyAre() {
        let stroke = [Route(color: 0.7, alpha: 1), Route(color: 0.9, alpha: 0, camera: true)]
        for x: Float in [0, 0.5, 1] {
            XCTAssertEqual(composite(stroke, pal: 0.2, fade: x, realOnTop: true), 0.7, accuracy: 1e-6,
                           "real over pal: the stroke whole")
            XCTAssertEqual(composite(stroke, pal: 0.2, fade: x, realOnTop: false), 0.2, accuracy: 1e-6,
                           "pal over real: the pal whole over it")
        }
    }

    /// a stroke over the camera: whole over it real on top, and the pal does
    /// not thin over it pal on top
    func testStrokeOverTheCamera() {
        let routes = [Route(color: 0.9, alpha: 1, camera: true), Route(color: 0.7, alpha: 1)]
        for x: Float in [0, 0.5, 1] {
            XCTAssertEqual(composite(routes, pal: 0.2, fade: x, realOnTop: true), 0.7, accuracy: 1e-6)
            XCTAssertEqual(composite(routes, pal: 0.2, fade: x, realOnTop: false), 0.2, accuracy: 1e-6)
        }
    }

    /// the camera over a stroke, pal on top: the pal thins over the camera,
    /// which covers the stroke
    func testCameraOverAStroke() {
        let routes = [Route(color: 0.7, alpha: 1), Route(color: 0.9, alpha: 1, camera: true)]
        XCTAssertEqual(composite(routes, pal: 0.2, fade: 0.5, realOnTop: false), 0.55, accuracy: 1e-6)
        XCTAssertEqual(composite(routes, pal: 0.2, fade: 1, realOnTop: false), 0.9, accuracy: 1e-6)
    }

    /// a camera at half its slider moves half the pal aside
    func testHalfCameraThinsHalfThePal() {
        XCTAssertEqual(RouterNode.palOverCamera(1, share: 0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(RouterNode.palOverCamera(0.5, share: 1), 0.5, accuracy: 1e-6)
        XCTAssertEqual(RouterNode.palOverCamera(0, share: 1), 1, accuracy: 1e-6)
        XCTAssertEqual(RouterNode.palOverCamera(1, share: 0), 1, accuracy: 1e-6)
    }

    /// 0 is the pal alone and 1 the camera alone, either way round
    func testEnds() {
        let cam = [Route(color: 0.9, alpha: 1, camera: true)]
        for realOnTop in [true, false] {
            XCTAssertEqual(composite(cam, pal: 0.2, fade: 0, realOnTop: realOnTop), 0.2, accuracy: 1e-6)
            XCTAssertEqual(composite(cam, pal: 0.2, fade: 1, realOnTop: realOnTop), 0.9, accuracy: 1e-6)
        }
    }
}
