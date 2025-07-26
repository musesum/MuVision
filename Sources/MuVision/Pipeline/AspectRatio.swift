//  created by musesum on 8/3/21.
//

import UIKit

/** create a clipping rect where x,y is inside boundary, not offset
 - Parameters:
 - from: sourc size to rescale and clip
 - to: destination size in which to fill
 */
public func fillClip(in i: CGSize,
                     out o: CGSize) -> CGRect {

    let ow = o.width    // out width
    let oh = o.height   // out height
    let oa = ow/oh      // out aspect

    let iw = i.width
    let ih = i.height
    let ia = iw/ih          // in aspect

    if oa < ia { // portrait < landscape

        let h = oh            // use out height
        let w = iw * (oh/ih)  // rescale width to fill
        let x = (w-ow) / 2    // beginning x offset

        return CGRect(x: x, y: 0, width: w, height: h)

    } else if oa > ia { // landscape > portrait

        let w = ow          // us out width
        let h = ih * (ow/iw)// rescale height to fill
        let y = (h-oh) / 2  // beginning y offset

        return CGRect(x: 0, y: y, width: w, height: h)

    } else {

        return CGRect(x: 0, y: 0, width: ow, height: oh)
    }
}

// get normalized clipping frame
public func texClip(in inTex: MTLTexture?,
                    out outTex: MTLTexture?) -> CGRect? {

    if  let inTex,
        let outTex {

        // input i
        let iw = CGFloat(inTex.width)
        let ih = CGFloat(inTex.height)
        let ia = iw/ih // in aspect

        // output o
        let ow = CGFloat(outTex.width)
        let oh = CGFloat(outTex.height)
        let oa = ow/oh // out aspect

        let r: CGRect

        if oa < ia { // ipad front, back

            r =  CGRect(x      : round((iw - ih*oa)/2),
                        y      : 0,
                        width  : iw,
                        height : ih)

        } else { // phone front, back (1.218)

            r = CGRect(x      : 0,
                       y      : round((ih - iw/oa)/2),
                       width  : iw,
                       height : ih)
        }
        return r
    }
    return nil
}
