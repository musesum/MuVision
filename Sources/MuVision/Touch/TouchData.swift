// created by musesum on 6/26/25

import UIKit

public struct TouchData {
    let force    : Float
    let radius   : Float
    let nextXY   : CGPoint
    let phase    : Int
    let azimuth  : CGFloat
    let altitude : CGFloat
    let key      : Int

    public init(force    : Float,
                radius   : Float,
                nextXY   : CGPoint,
                phase    : Int,
                azimuth  : CGFloat,
                altitude : CGFloat,
                key      : Int) {

        self.force    = force
        self.radius   = radius
        self.nextXY   = nextXY
        self.phase    = phase
        self.azimuth  = azimuth
        self.altitude = altitude
        self.key      = key
    }
}
