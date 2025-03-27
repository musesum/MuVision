
import QuartzCore
import UIKit
import MuFlo

public class TouchDraw {

    public static var shared = TouchDraw()

    private var root     : Flo?
    private var tilt˚    : Flo? ; var tilt    = false
    private var press˚   : Flo? ; var press   = true
    private var size˚    : Flo? ; var size    = CGFloat(1)
    private var index˚   : Flo? ; var index   = UInt32(255)
    private var prev˚    : Flo? ; var prev    = CGPoint.zero
    private var next˚    : Flo? ; var next    = CGPoint.zero
    private var force˚   : Flo? ; var force   = CGFloat(0)
    private var radius˚  : Flo? ; var radius  = CGFloat(0)
    private var azimuth˚ : Flo? ; var azimuth = CGPoint.zero
    private var fill˚    : Flo? ; var fill    = Float(-1)

    private var bufSize = CGSize.zero
    private var drawBuf: UnsafeMutablePointer<UInt32>?
    private var archiveFlo: ArchiveFlo?
    public var drawableSize = CGSize.zero
    public var drawUpdate: MTLTexture?
    private var drawDot: MidiDrawDot?
    private var drawRipple: MidiDrawRipple?

    public func parseRoot(_ root: Flo,
                          _ archiveFlo: ArchiveFlo) {

        self.root = root
        self.archiveFlo = archiveFlo
        //self.drawDot = MidiDrawDot(root, archiveFlo, "sky.draw.dot" )
        self.drawRipple = MidiDrawRipple(root, archiveFlo, "sky.draw.ripple")

        let sky    = root.bind("sky"   )
        let input  = sky .bind("input" )
        let draw   = sky .bind("draw"  )
        let brush  = draw.bind("brush" )
        let line   = draw.bind("line"  )
        let screen = draw.bind("screen")

        tilt˚    = input .bind("tilt"   ){ f,_ in self.tilt    = f.bool    }
        press˚   = brush .bind("press"  ){ f,_ in self.press   = f.bool    }
        size˚    = brush .bind("size"   ){ f,_ in self.size    = f.cgFloat }
        index˚   = brush .bind("index"  ){ f,_ in self.index   = f.uint32  }
        prev˚    = line  .bind("prev"   ){ f,_ in self.prev    = f.cgPoint }
        next˚    = line  .bind("next"   ){ f,_ in self.next    = f.cgPoint }
        force˚   = input .bind("force"  ){ f,_ in self.force   = f.cgFloat }
        radius˚  = input .bind("radius" ){ f,_ in self.radius  = f.cgFloat }
        azimuth˚ = input .bind("azimuth"){ f,_ in self.azimuth = f.cgPoint }
        fill˚    = screen.bind("fill"   ){ f,_ in self.fill    = f.float   }
    }
}
extension TouchDraw {
    /// get radius of TouchCanvasItem
    public func updateRadius(_ item: TouchCanvasItem) -> CGFloat {

        let visit = item.visit()

        // if using Apple Pencil and brush tilt is turned on
        if item.force > 0, tilt {
            let azi = CGPoint(x: CGFloat(-item.azimY), y: CGFloat(-item.azimX))
            azimuth˚?.setAnyExprs(azi, .fire, visit)
            //PrintGesture("azimuth dXY(%.2f,%.2f)", item.azimuth.dx, item.azimuth.dy)
        }

        // if brush press is turned on
        var radiusNow = CGFloat(1)
        if press {
            if force > 0 || item.azimX != 0.0 {
                force˚?.setAnyExprs(item.force, .fire, visit) // will update local azimuth via FloGraph
                radiusNow = size
            } else {
                radius˚?.setAnyExprs(item.radius, .fire, visit)
                radiusNow = radius
            }
        } else {
            radiusNow = size
        }
        return radiusNow
    }
    @inline(__always)
    public func drawPoint(_ point: CGPoint,
                          _ radius: CGFloat) {

        guard let drawBuf else { return }
        if point == .zero { return }

        #if os(visionOS)
        let scale = CGFloat(3)
        #else
        let scale = UIScreen.main.scale
        #endif

        let viewPoint = point * scale
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
    }
    @inline(__always)
    public func touchViewToTex(_ touch: CGPoint,
                               _ drawableSize: CGSize,
                               _ texSize: CGSize) -> CGPoint {

        let clipFill = fillClip(in: texSize, out: drawableSize)
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
extension TouchDraw {
    
    @inline(__always)
    public func drawIntoBuffer(_ drawBuf: UnsafeMutablePointer<UInt32>,
                               _ drawSize: CGSize) {

        self.drawBuf = drawBuf
        self.bufSize = drawSize

        let drawWidth  : Int
        let drawHeight : Int
        switch drawSize.aspect {
        case .landscape:
            drawWidth  = Int(drawSize.width)
            drawHeight = Int(drawSize.height)
        default:
            drawWidth  = Int(drawSize.height)
            drawHeight = Int(drawSize.width)
        }
        let drawCount = drawWidth * drawHeight // count

        if updateDraw() {
            // fill with mtl texture
        } else if fill > 255 {
            drawFill(UInt32(fill))
        } else if fill >= 0 {
            let v8 = UInt32(fill * 255)
            let fill = (v8 << 24) + (v8 << 16) + (v8 << 8) + v8
            drawFill(fill)
        }
        self.fill = -1

        // fill with mtl texture
        func updateDraw() -> Bool {
            guard let drawUpdate,
                  let updateData = drawUpdate.rawData() else { return false }

            let updateWidth  : Int
            let updateHeight : Int
            switch drawUpdate.aspect {
            case .landscape:
                updateWidth  = Int(drawUpdate.width)
                updateHeight = Int(drawUpdate.height)
            default:
                updateWidth  = Int(drawUpdate.height)
                updateHeight = Int(drawUpdate.width)
            }

            let clipWidth = min(drawWidth, updateWidth)
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
            DebugLog { P("📋 updateDraw bufSize\(drawSize.digits(0))") }
            self.drawUpdate = nil
            return true
        }
        func drawFill(_ fill: UInt32) {
            for i in 0 ..< drawCount {
                drawBuf[i] = fill
            }
        }
    }
}
