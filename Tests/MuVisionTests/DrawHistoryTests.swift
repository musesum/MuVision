// created by musesum on 9/20/26

import XCTest
import Metal
import MuFlo
@testable import MuVision

/// the canvas's undo ring. Both arrows live on the real paint leaf's bottom
/// row, so they step that layer's own history: the newest snapshot carrying
/// a real texture, with the settings the real leaf writes. A false stroke's
/// snapshot stays where it is, and nothing on either list reaches the cube
final class DrawHistoryTests: XCTestCase {

    /// canvas.alpha is the cube face mix and the plato alpha, written by the
    /// hand and by no menu control. It was on the snapshot list, so the first
    /// undo pushed mixcube's y back to 0 and the cube went dark
    func testSnapshotsLeaveTheCubeAlone() {
        for path in DrawNode.realParamPaths + DrawNode.indexParamPaths {
            XCTAssertNotEqual(path, "canvas.alpha", "the cube is not the canvas's to roll back")
        }
    }

    /// the real leaf's own settings ride with the real layer, the false
    /// leaf's with the index layer, and neither list carries the other's
    func testParamListsAreKeptApart() {
        let real = Set(DrawNode.realParamPaths)
        let index = Set(DrawNode.indexParamPaths)
        // the stroke colour is the one both leaves write, each with its own
        // layer in w; restoreSnap keeps a snapshot from the other layer out
        XCTAssertEqual(real.intersection(index), ["canvas.brush.paint"])
        XCTAssertTrue(real.contains("canvas.brush.alpha"), "the real left arc's stroke alpha")
        XCTAssertTrue(real.contains("canvas.shiftReal"))
        XCTAssertFalse(real.contains("canvas.shift"), "the false pad's shift is not the real one's")
        XCTAssertFalse(real.contains("canvas.brush.index"), "the false brush row stays put")
        XCTAssertFalse(real.contains("sky.color.xfade"), "and so do the palettes")
        XCTAssertTrue(index.contains("canvas.brush.index"))
        XCTAssertTrue(index.contains("sky.color.ofs0"))
    }

    /// the arrows step over an index-only snapshot to the newest real one,
    /// and leave the index ones in the ring
    func testPopRealStepsOverTheFalseLayer() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        func tex() throws -> MTLTexture { try XCTUnwrap(device.makeTexture(descriptor: d)) }
        func snap(real: Bool) throws -> DrawNode.CanvasSnap {
            DrawNode.CanvasSnap(index: real ? nil : try tex(),
                                real: real ? try tex() : nil,
                                params: [], strings: [])
        }
        var snaps = [try snap(real: true), try snap(real: false), try snap(real: false)]

        let first = DrawNode.popReal(&snaps)
        XCTAssertNotNil(first?.real, "the newest real one")
        XCTAssertEqual(snaps.count, 2, "both false snapshots stay")
        XCTAssertTrue(snaps.allSatisfy { $0.real == nil })

        XCTAssertNil(DrawNode.popReal(&snaps), "nothing left for the real arrows")
        XCTAssertEqual(snaps.count, 2, "and the false ones are still not touched")
    }
}
