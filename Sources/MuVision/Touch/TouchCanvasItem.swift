import UIKit
import MuFlo

public struct TouchCanvasItem: Codable, TimedItem, Sendable {

    public let key    : Int    // unique id of touch
    public let time   : Double // time event was created
    public let nextX  : Float  // touch point x
    public let nextY  : Float  // touch point y
    public let force  : Float  // pencil pressure
    public let radius : Float  // size of dot
    public let azimX  : Double // pencil tilt X
    public let azimY  : Double // pencil tilt Y
    public let phase  : Int    // UITouch.Phase.rawValue
    public let type   : Int    // Visitor.type

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
    init(_ prevItem: TouchCanvasItem? = nil,
         _ touch: UITouch) async {

        let actor = TouchDataActor()
        let touch = await actor.make(from: touch)
        var force = touch.force
        var radius = touch.radius
        
        let alti = (.pi/2 - touch.altitude) / .pi/2
        let azim = CGVector(dx: -sin(touch.azimuth) * alti, dy: cos(touch.azimuth) * alti)
        if let prevItem {
            let forceFilter = Float(0.90)
            force = (prevItem.force * forceFilter) + (force * (1-forceFilter))

            let radiusFilter = Float(0.95)
            radius = (prevItem.radius * radiusFilter) + (radius * (1-radiusFilter))
            //print(String(format: "* %.3f -> %.3f", lastItem.force, force))
        } else {
            force = 0 // bug: always begins at 0.5
        }

        self.time   = Date().timeIntervalSince1970
        self.key    = touch.key
        self.nextX  = Float(touch.nextXY.x)
        self.nextY  = Float(touch.nextXY.y)
        self.radius = Float(touch.radius)
        self.force  = force
        self.azimX  = azim.dx
        self.azimY  = azim.dy
        self.phase  = touch.phase
        self.type   = VisitType.canvas.rawValue
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
    init(repeated: TouchCanvasItem) {

        self.time   = Date().timeIntervalSince1970
        self.key    = repeated.key
        self.nextX  = repeated.nextX
        self.nextY  = repeated.nextY
        self.radius = repeated.radius
        self.force  = repeated.force
        self.azimX  = repeated.azimX
        self.azimY  = repeated.azimY
        self.phase  = repeated.phase
        self.type   = repeated.type
    }
    func repeated() -> TouchCanvasItem {
        return TouchCanvasItem(repeated: self)
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
    var isDone:  Bool {
        return (phase == UITouch.Phase.ended    .rawValue ||
                phase == UITouch.Phase.cancelled.rawValue )
    }
}

