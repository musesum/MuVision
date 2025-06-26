// created by musesum on 6/26/25

import UIKit

struct TouchData {
    var force    : Float
    var radius   : Float
    var nextXY   : CGPoint
    var phase    : Int
    var azimuth  : CGFloat
    var altitude : CGFloat
    var key      : Int
}

actor TouchDataActor {
    func make(from touch: UITouch) async -> TouchData {
        await MainActor.run {
            TouchData(
                force    : Float(touch.force),
                radius   : Float(touch.majorRadius),
                nextXY   : touch.preciseLocation(in: nil),
                phase    : touch.phase.rawValue,
                azimuth  : touch.azimuthAngle(in: nil),
                altitude : touch.altitudeAngle,
                key      : touch.hash
            )
        }
    }
}
