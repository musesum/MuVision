
import UIKit
import MuFlo

public struct TouchCanvasItem: Codable {

    public var key    : Int      // unique id of touch
    public var time   : Double   // time event was created
    public var nextX  : Float    // touch point x
    public var nextY  : Float    // touch point y
    public var force  : Float    // pencil pressure
    public var radius : Float    // size of dot
    public var azimX  : Double   // pencil tilt X
    public var azimY  : Double   // pencil tilt Y
    public var phase  : Int      // UITouch.Phase.rawValue
    public var type   : Int      // Visitor.type

    public init(_ key     : Int,
                _ next    : CGPoint,
                _ radius  : Float,
                _ force   : Float,
                _ azimuth : CGVector,
                _ phase   : Int, //UITouch.Phase,
                _ visit   : Visitor) {

        // tested timeDrift between UITouches.time and Date() is around 30 msec
        self.time   = Date().timeIntervalSince1970
        self.key    = key
        self.nextX  = Float(next.x)
        self.nextY  = Float(next.y)
        self.radius = Float(radius)
        self.force  = Float(force)
        self.azimX  = azimuth.dx
        self.azimY  = azimuth.dy
        self.phase  = phase
        self.type   = visit.type.rawValue

    }
    
    var cgPoint: CGPoint { get {
        CGPoint(x: CGFloat(nextX), y: CGFloat(nextY))
    }}
    var visitFrom: String {
        VisitType(rawValue: type).log
    }
    public func visit() -> Visitor {
        return Visitor(0, VisitType(rawValue: type))
    }
    func logTouch() {
        if phase == UITouch.Phase.began.rawValue { print() } // space for new stroke
        print(String(format:"%.3f →(%3.f,%3.f) 𝝙%5.1f f: %.3f r: %.2f %s",
                     time, nextX, nextY, force, radius, visitFrom))
    }
    func isDone() -> Bool {
        return (phase == UITouch.Phase.ended    .rawValue ||
                phase == UITouch.Phase.cancelled.rawValue )
    }
}

