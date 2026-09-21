//  created by musesum on 9/19/26.

import CoreImage
import CoreGraphics
import Metal

/// the render's flat texture as each cube face shows it, looked at straight
/// on from inside: the render's own index cube, run over a small snapshot,
/// so F and B show the flat, R and L mirror it, and U and D fold its top and
/// bottom triangles the way the cube does. For plato.cube's leaf, a few
/// times a second while it shows
public final class CubeFaces {

    public let side: Int
    private let index: CubemapIndex
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let space = CGColorSpaceCreateDeviceRGB()

    /// an even side: the index's four triangles then cover every texel
    public init(side: Int = 64) {
        self.side = max(2, side & ~1)
        index = CubemapIndex(CGSize(width: self.side, height: self.side))
    }

    /// the flat, cropped square about its centre as the render's index is --
    /// at most 2048 across -- and `side` texels across, its top row first as
    /// the screen shows it
    public func flat(_ tex: MTLTexture) -> CGImage? {
        guard let read = CIImage(mtlTexture: tex, options: nil) else { return nil }
        // pipeline textures are top-down, CoreImage bottom-up
        let up = read.oriented(.downMirrored)
        let e = up.extent
        let s = min(e.width, e.height, 2048)
        guard s > 0 else { return nil }
        let square = up.cropped(to: CGRect(x: e.midX - s / 2, y: e.midY - s / 2, width: s, height: s))
        let scale = CGFloat(side) / s
        let small = square
            .transformed(by: CGAffineTransform(translationX: -square.extent.minX, y: -square.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        return autoreleasepool { context.createCGImage(small, from: rect) }
    }

    /// F R B L U D from the flat, each `side` texels square, top row first
    public func faces(_ flat: CGImage) -> [CGImage] {
        guard let src = pixels(flat) else { return [] }
        return CubeFace.allCases.compactMap { face in
            image(remap(src, quad(face)))
        }
    }

    /// the index quad the viewer sees as `face`: R samples `left`, L `right`
    func quad(_ face: CubeFace) -> Quad {
        switch face {
        case .front : return index.front
        case .right : return index.left
        case .back  : return index.back
        case .left  : return index.right
        case .up    : return index.top
        case .down  : return index.bot
        }
    }

    /// each face texel takes the flat texel its index points at; the index
    /// holds texel/side, so rounding recovers the texel
    func remap(_ src: [UInt8], _ quad: Quad) -> [UInt8] {
        var dst = [UInt8](repeating: 0, count: side * side * 4)
        let n = Float(side)
        for i in 0 ..< min(quad.count, side * side) {
            let (u, v) = quad[i]
            guard u >= 0, v >= 0 else { continue }
            let x = min(side - 1, max(0, Int((Float(u) * n).rounded())))
            let y = min(side - 1, max(0, Int((Float(v) * n).rounded())))
            let s = (y * side + x) * 4
            let d = i * 4
            dst[d] = src[s]; dst[d + 1] = src[s + 1]; dst[d + 2] = src[s + 2]; dst[d + 3] = src[s + 3]
        }
        return dst
    }

    /// RGBA, premultiplied, top row first
    func pixels(_ image: CGImage) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? buf : nil
    }
    func image(_ rgba: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
