// created by musesum on 3/28/25

import UIKit

public protocol TouchDrawProtocol {
    func drawPoint(
        _ point: CGPoint,
        _ scale: CGFloat,
        _ radius: CGFloat,
        _ bufSize: CGSize,
        _ drawableSize: CGSize,
        _ index: UInt32, // brushIndex
        _ drawBuf: UnsafeMutablePointer<UInt32>?)

    func drawIntoBuffer(
        _ drawBuf: UnsafeMutablePointer<UInt32>,
        _ drawSize: CGSize,
        _ drawTex: MTLTexture?,
        _ fill: inout Float) -> Bool
}

#if DEBUG
/// this is a problem with SPM not allowing targeted optimizations
/// The solution would be to compile binararies for each target.
/// Not worth the complexity of workflow for naive coders.
#warning("TouchDrawDot drawing large Dots will be slow in DEBUG mode.")
#endif

open class TouchDrawDot: TouchDrawProtocol {

    public init() {}
    public func drawPoint(
        _ point: CGPoint,
        _ scale: CGFloat,
        _ radius: CGFloat,
        _ bufSize: CGSize,
        _ drawableSize: CGSize,
        _ index: UInt32, // brushIndex
        _ drawBuf: UnsafeMutablePointer<UInt32>?)
    {
        guard let drawBuf else { return }
        if point == .zero { return }
        let viewPoint = CGPoint(x: point.x * scale, y: point.y * scale)
        let texPoint = touchViewToTex(viewPoint, drawableSize, bufSize)

        let r = radius * 2.0 - 1
        let r2 = Int(r * r / 4.0)
        let texW = Int(bufSize.width)
        let texH = Int(bufSize.height)
        let texMax = Int(bufSize.width * bufSize.height)
        let texX = Int(texPoint.x)
        let texY = Int(texPoint.y)

        var x0 = Int(texPoint.x - radius - 0.5)
        var y0 = Int(texPoint.y - radius - 0.5)
        var x1 = Int(texPoint.x + radius + 0.5)
        var y1 = Int(texPoint.y + radius + 0.5)

        while x0 < 0 { x0 += texW }
        while y0 < 0 { y0 += texH }
        while x1 < x0 { x1 += texW }
        while y1 < y0 { y1 += texH }

        if radius == 1 {
            drawBuf[y0 * texW + x0] = index
            return
        }

        for y in y0 ..< y1 {

            for x in x0 ..< x1  {

                let xd = (x - texX) * (x - texX)
                let yd = (y - texY) * (y - texY)

                if xd + yd < r2 {

                    let yy = (y + texH) % texH  // wrapped pixel y index
                    let xx = (x + texW) % texW  // wrapped pixel x index
                    let ii = (yy * texW + xx) % texMax // final pixel x, y index into buffer

                    drawBuf[ii] = index     // set the buffer to value
                }
            }
        }

        func touchViewToTex(
            _ touch: CGPoint,
            _ drawableSize: CGSize,
            _ texSize: CGSize) -> CGPoint
        {
            let clipFill = fillClip(in: texSize, out: drawableSize) //... duplicate
            let clipNorm = clipFill.normalize()

            let clipX_ = clipNorm.minX
            let clipY_ = clipNorm.minY
            let clipW_ = clipNorm.width
            let clipH_ = clipNorm.height

            let touchX_ = touch.x / drawableSize.width
            let touchY_ = touch.y / drawableSize.height

            let texW = texSize.width
            let texH = texSize.height

            let xTex = (touchX_ * clipW_ + clipX_) * texW
            let yTex = (touchY_ * clipH_ + clipY_) * texH

            let result = CGPoint(x: xTex, y: yTex)

            return result
        }
    }

    public func drawIntoBuffer(
        _ drawBuf: UnsafeMutablePointer<UInt32>,
        _ drawSize: CGSize,
        _ drawTex: MTLTexture? = nil,
        _ fill: inout Float) -> Bool
    {
        let drawWidth  = Int(max(drawSize.width, drawSize.height))
        let drawHeight = Int(min(drawSize.width, drawSize.height))

        let drawCount = drawWidth * drawHeight // count
        var eraseDrawTex: Bool = false
        if updateDraw() {
            // now filled with mtl texture
            eraseDrawTex = true
        } else if fill > 255 {
            drawFill(UInt32(fill))
        } else if fill >= 0 {
            let v8 = UInt32(fill * 255)
            let fill = (v8 << 24) + (v8 << 16) + (v8 << 8) + v8
            drawFill(fill)
        }
        fill = -1
        return eraseDrawTex

        // fill with mtl texture
        func updateDraw() -> Bool {
            guard let drawTex,
                  let updateData = drawTex.rawData() else { return false }

            let updateWidth  = Int(max(drawSize.width, drawSize.height))
            let updateHeight = Int(min(drawSize.width, drawSize.height))
            let clipWidth  = min(drawWidth, updateWidth)
            let clipHeight = min(drawHeight, updateHeight)

            updateData.withUnsafeBytes { updatePtr in
                let update32Ptr = updatePtr.bindMemory(to: UInt32.self)
                for y in 0 ..< clipHeight {
                    for x in 0 ..< clipWidth {
                        let ui = y * updateWidth + x
                        let di = y * drawWidth + x
                        drawBuf[di] = update32Ptr[ui]
                    }
                }
            }
            //DebugLog { P("📋 updateDraw drawSize\(drawSize.digits(0))") }
            //.... self.drawUpdate = nil
            return true
        }
        func drawFill(_ fill: UInt32) {
            for i in 0 ..< drawCount {
                drawBuf[i] = fill
            }
        }
    }
}
