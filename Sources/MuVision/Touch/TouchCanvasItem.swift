
import UIKit
import MuFlo


public struct TouchCanvasItem: Codable, TimedItem {
    
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
                _ phase   : UITouch.Phase,
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
        self.phase  = Int(phase.rawValue)
        self.type   = visit.type.rawValue
    }
    init(_ lastItem: TouchCanvasItem? = nil,
         _ key     : Int,
         _ force   : CGFloat,
         _ radius  : CGFloat,
         _ next    : CGPoint,
         _ phase   : UITouch.Phase,
         _ azimuth : CGFloat,
         _ altitude: CGFloat,
         _ visit   : Visitor) {

        let alti = (.pi/2 - altitude) / .pi/2
        let azim = CGVector(dx: -sin(azimuth) * alti, dy: cos(azimuth) * alti)
        var force = Float(force)
        var radius = Float(radius)

        if let lastItem {

            let forceFilter = Float(0.90)
            force = (lastItem.force * forceFilter) + (force * (1-forceFilter))

            let radiusFilter = Float(0.95)
            radius = (lastItem.radius * radiusFilter) + (radius * (1-radiusFilter))
            //print(String(format: "* %.3f -> %.3f", lastItem.force, force))
        } else {
            force = 0 // bug: always begins at 0.5
        }
        self.time   = Date().timeIntervalSince1970
        self.key    = key
        self.nextX  = Float(next.x)
        self.nextY  = Float(next.y)
        self.radius = Float(radius)
        self.force  = Float(force)
        self.azimX  = azim.dx
        self.azimY  = azim.dy
        self.phase  = Int(phase.rawValue)
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

