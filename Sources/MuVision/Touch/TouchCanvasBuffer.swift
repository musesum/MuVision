//  created by musesum on 8/22/23.

import UIKit
import MuFlo
import MuPeers

open class TouchCanvasBuffer {

    // repeat last touch until isDone
    private var repeatLastItem: TouchCanvasItem?

    // each finger or brush gets its own double buffer
    private let buffer = DoubleBuffer<TouchCanvasItem>(internalLoop: false)
    private var indexNow = 0
    private var touchCanvas: TouchCanvas
    private var isDone = false
    private var touchCubic = TouchCubic()

    public init(_ touch: UITouch,
                _ touchCanvas: TouchCanvas) {

        self.touchCanvas = touchCanvas
        buffer.delegate = self
        addTouchItem(touch)
    }

    public init(_ touchItem: TouchCanvasItem,
                _ touchCanvas: TouchCanvas) {

        self.touchCanvas = touchCanvas
        buffer.delegate = self

        addTouchCanvasItem(touchItem)
    }

    public init(_ jointState: JointState,
                _ touchCanvas: TouchCanvas) {

        self.touchCanvas = touchCanvas
        buffer.delegate = self

        addTouchHand(jointState)
    }

    public func addTouchHand(_ jointState: JointState) {

        let force = CGFloat(jointState.pos.z) * -200
        let radius = force
        let nextXY = CGPoint(x: CGFloat( jointState.pos.x * 400 + 800),
                             y: CGFloat(-jointState.pos.y * 400 + 800))

        let phase = jointState.phase
        let azimuth = CGFloat.zero
        let altitude = CGFloat.zero

        logTouch(phase, nextXY, radius)

        let item = makeTouchCanvasItem(jointState.hash, force, radius, nextXY, phase, azimuth, altitude, Visitor(0, .canvas))

        buffer.append(item)
        Task {
            await touchCanvas.peers.sendItem(.touch) {
                do {
                    return try JSONEncoder().encode(item)
                } catch {
                    print(error)
                    return nil
                }
            }
        }
    }


    // TODO:  separate out //??
    var posX: ClosedRange<CGFloat>?
    var posY: ClosedRange<CGFloat>?
    var radi: ClosedRange<CGFloat>?

    func logTouch(_ phase: UITouch.Phase,
                  _ nextXY: CGPoint,
                  _ radius: CGFloat) {

        switch phase {
        case .began : logNow("\n👍🟢") ; resetRanges()
        case .moved : logNow("🫰🔷")   ; setRanges()
        case .ended : logNow("🖐️🛑")   ; setRanges(); logRanges()
        default     : PrintLog("🖐️⁉️")
        }
        func logNow(_ msg: String) {
            //PrintLog("\(msg)(\(nextXY.x.digits(0...2)), \(nextXY.y.digits(0...2)), \(radius.digits(0...2)))", terminator: " ")
        }
        func resetRanges() {
            posX = nil
            posY = nil
            radi = nil
            setRanges()
        }
        func setRanges() {
            if posX == nil { posX = nextXY.x...nextXY.x }
            else if let xx = posX { posX = min(xx.lowerBound, nextXY.x)...max(xx.upperBound, nextXY.x) }
            if posY == nil { posY = nextXY.y...nextXY.y}
            else if let yy = posY {  posY = min(yy.lowerBound, nextXY.y)...max(yy.upperBound, nextXY.y) }
            if radi == nil { radi = radius...radius }
            else if let rr = radi { radi = min(rr.lowerBound, radius)...max(rr.upperBound, radius) }
        }
        func logRanges() {
            if let posX, let posY, let radi {
                let xStr = "\(posX.lowerBound.digits(0))…\(posX.upperBound.digits(0))"
                let yStr = "\(posY.lowerBound.digits(0))…\(posY.upperBound.digits(0))"
                let rStr = "\(radi.lowerBound.digits(0))…\(radi.upperBound.digits(0))"
                NoDebugLog { P("👐 (\(xStr), \(yStr), \(rStr))") }
            }
        }
    }

    public func addTouchCanvasItem(_ touchItem: TouchCanvasItem) {
        buffer.append(touchItem)
    }

    public func addTouchItem(_ touch: UITouch) {

        let force = touch.force
        let radius = touch.majorRadius
        let nextXY = touch.preciseLocation(in: nil)
        let phase = touch.phase
        let azimuth = touch.azimuthAngle(in: nil)
        let altitude = touch.altitudeAngle

        //logTouch(phase, nextXY, radius)
        
        let item = makeTouchCanvasItem(touch.hash, force, radius, nextXY, phase, azimuth, altitude, Visitor(0, .canvas))

        buffer.append(item)

        Task {
            await touchCanvas.peers.sendItem(.touch) {
                do {
                    return try JSONEncoder().encode(item)
                } catch {
                    print(error)
                    return nil
                }
            }
        }
    }

    public func makeTouchCanvasItem(
        _ key     : Int,
        _ force   : CGFloat,
        _ radius  : CGFloat,
        _ nextXY  : CGPoint,
        _ phase   : UITouch.Phase,
        _ azimuth : CGFloat,
        _ altitude: CGFloat,
        _ visit   : Visitor) -> TouchCanvasItem {

            let alti = (.pi/2 - altitude) / .pi/2
            let azim = CGVector(dx: -sin(azimuth) * alti, dy: cos(azimuth) * alti)
            var force = Float(force)
            var radius = Float(radius)

            if let repeatLastItem {

                let forceFilter = Float(0.90)
                force = (repeatLastItem.force * forceFilter) + (force * (1-forceFilter))

                let radiusFilter = Float(0.95)
                radius = (repeatLastItem.radius * radiusFilter) + (radius * (1-radiusFilter))
                //print(String(format: "* %.3f -> %.3f", lastItem.force, force))
            } else {
                force = 0 // bug: always begins at 0.5
            }
            let item = TouchCanvasItem(key, nextXY, radius, force, azim, phase, visit)
            return item
        }

}
extension TouchCanvasBuffer: DoubleBufferDelegate {

    public typealias Item = TouchCanvasItem

    @discardableResult
    public func flushItem<Item>(_ item: Item) -> Bool {
        guard let item = item as? TouchCanvasItem else { return err("not TouchCanvasItem") }

        repeatLastItem = item

        let radius = touchCanvas.touchDraw.updateRadius(item)
        let point = item.cgPoint
        isDone = item.isDone()

        // 4 point cubic smoothing of line segment(s)
        touchCubic.addPointRadius(point, radius, isDone)
        touchCubic.drawPoints(touchCanvas.touchDraw.drawPoint)

        return isDone

        func err(_ msg: String) -> Bool {
            PrintLog("⁉️ TouchCanvasBuffer::flushItem: \(msg)")
            return false
        }
    }

    func flushTouches(_ touchRepeat: Bool) -> Bool {

        if buffer.isEmpty,
           touchRepeat,
             repeatLastItem != nil {
            // finger is stationary repeat last movement
            // don't update touchCubic.addPointRadius
            touchCubic.drawPoints(touchCanvas.touchDraw.drawPoint)
           
        } else {
            isDone = buffer.flushBuf()
        }
        return isDone
    }

}
