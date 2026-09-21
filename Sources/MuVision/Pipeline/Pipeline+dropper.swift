// created by musesum on 9/20/26

import Metal
import MuFlo

/// the real paint leaf's eyedropper, the frame's half of it.
///
/// `canvas.dropper.tap` 1 means a canvas tap is waiting for the colour under
/// it. The frame just presented is the only image that carries every layer --
/// the flat map or the cube, whichever ran, with plato drawn over it -- so the
/// read happens on the drawable itself, in `renderFrame`, while it is still in
/// scope. Nothing else keeps that image: `pipe.tile.out` is upstream of the
/// render map, so a pixel read there would miss the crop, the cube and plato.
///
/// The colour goes to `canvas.brush.paint`, the brush's own bus, and the `<>`
/// edge carries it to `canvas.real`, whose leaf moves its wheel thumb to the
/// colour it just picked
extension Pipeline {

    /// the point is in drawable pixels, the same units a stroke arrives in
    func pickDropper(_ tex: MTLTexture) {

        guard let dropper˚, (dropper˚.val("tap") ?? 0) > 0.5 else { return }

        // the tap is answered either way: a frame that cannot read its own
        // drawable must still let the button stop pulsing
        defer { dropper˚.setNameNums([("on", 0), ("tap", 0)], .fire, Visitor(0)) }

        // .private would need a blit into a buffer; no platform here hands
        // back a drawable that way, so say so rather than fail in silence
        guard tex.storageMode == .shared,
              let rgb = Rgb.texel(tex,
                                  Int(dropper˚.val("x") ?? 0),
                                  Int(dropper˚.val("y") ?? 0))
        else {
            return PrintLog("⁉️ dropper: no read of a \(tex.pixelFormat) " +
                            "\(tex.storageMode == .shared ? "shared" : "private") drawable")
        }
        let hsv = rgb.hsv()
        paint˚?.setNameNums([("x", Double(hsv.hue)),
                             ("y", Double(hsv.sat)),
                             ("z", Double(hsv.val)),
                             ("w", 1)], .fire, Visitor(0))
    }
}

extension Rgb {

    /// one texel of a bgra8 texture, the point clamped inside it. The
    /// drawable's bytes are in the same space the wheel's own colours are
    /// written in, so a colour reads back the way it was painted
    public static func texel(_ tex: MTLTexture, _ x: Int, _ y: Int) -> Rgb? {

        guard tex.pixelFormat == .bgra8Unorm ||
              tex.pixelFormat == .bgra8Unorm_srgb,
              tex.width > 0, tex.height > 0
        else { return nil }

        let px = min(tex.width  - 1, max(0, x))
        let py = min(tex.height - 1, max(0, y))
        var bgra = [UInt8](repeating: 0, count: 4)
        tex.getBytes(&bgra, bytesPerRow: 4,
                     from: MTLRegionMake2D(px, py, 1, 1), mipmapLevel: 0)

        return Rgb(r: Float(bgra[2]) / 255,
                   g: Float(bgra[1]) / 255,
                   b: Float(bgra[0]) / 255)
    }
}
