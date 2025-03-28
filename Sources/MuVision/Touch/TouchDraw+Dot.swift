// created by musesum on 3/27/25

import UIKit
import MuFlo

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
    // get normalized clipping frame
    public static func texClip(in inTex: MTLTexture?,
                               out outTex: MTLTexture?) -> CGRect? {

        if  let inTex,
            let outTex {

            // input
            let iw = CGFloat(inTex.width)
            let ih = CGFloat(inTex.height)
            let ia = iw/ih // in aspect

            // output
            let ow = CGFloat(outTex.width)
            let oh = CGFloat(outTex.height)
            let oa = ow/oh // out aspect

            let clip = (oa < ia
                      ? CGRect(x: round((iw - ih*oa)/2), y: 0,  width: iw, height: ih) // ipad front, back
                      : CGRect(x: 0, y: round((ih - iw/oa)/2),  width: iw, height: ih))// phone front, back (1.218)
            return clip
        }
        return nil
    }
}

extension TouchDraw {

    public func drawPoint(_ point: CGPoint,
                          _ radius: CGFloat) {
        #if os(visionOS)
        let scale = CGFloat(3)
        #else
        let scale = UIScreen.main.scale
        #endif

        drawProto?.drawPoint(point, scale, radius, bufSize, drawableSize, index, drawBuf)
    }
    public func drawIntoBuffer(_ drawBuf: UnsafeMutablePointer<UInt32>,
                               _ drawSize: CGSize) {
        self.drawBuf = drawBuf
        self.bufSize = drawSize

        if let drawProto, drawProto.drawIntoBuffer(drawBuf, drawSize, drawTex, &fill) {
            self.drawTex = nil
        }
    }
}
