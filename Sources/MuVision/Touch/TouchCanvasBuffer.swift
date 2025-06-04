//  created by musesum on 8/22/23.

import UIKit
import MuFlo
import MuPeers

open class TouchCanvasBuffer {
    
    // repeat last touch until isDone
    private var repeatLastItem: TouchCanvasItem?
    
    // each finger or brush gets its own double buffer
    public let buffer = CircleBuffer<TouchCanvasItem>(capacity: 5, internalLoop: false)
    private var indexNow = 0
    private var canvas: TouchCanvas
    private var isDone = false
    private var touchCubic = TouchCubic()
    private var touchLog = TouchLog()
    
    public init(_ touch: UITouch,
                _ canvas: TouchCanvas) {
        
        self.canvas = canvas
        buffer.delegate = self
        addTouchItem(touch)
    }
    
    public init(_ item: TouchCanvasItem,
                _ canvas: TouchCanvas) {

        self.canvas = canvas
        buffer.delegate = self
        buffer.addItem(item, bufferType: .remote)
    }
    
    public init(_ joint: JointState,
                _ canvas: TouchCanvas) {
        
        self.canvas = canvas
        buffer.delegate = self
        
        addTouchHand(joint)
    }
    
    public func addTouchHand(_ joint: JointState) {
        
        let force = CGFloat(joint.pos.z) * -200
        let radius = force
        let nextXY = CGPoint(x: CGFloat( joint.pos.x * 400 + 800),
                             y: CGFloat(-joint.pos.y * 400 + 800))
        
        let phase = joint.phase
        let azimuth = CGFloat.zero
        let altitude = CGFloat.zero
        
        touchLog.log(phase, nextXY, radius)
        
        let item = makeTouchCanvasItem(joint.hash, force, radius, nextXY, phase, azimuth, altitude, Visitor(0, .canvas))
        
        buffer.addItem(item, bufferType: .local)
        Task {
            await canvas.peers.sendItem(.touchFrame) {
                do {
                    return try JSONEncoder().encode(item)
                } catch {
                    print(error)
                    return nil
                }
            }
        }
    }

    public func addTouchItem(_ touch: UITouch) {
        
        let force = touch.force
        let radius = touch.majorRadius
        let nextXY = touch.preciseLocation(in: nil)
        let phase = touch.phase
        let azimuth = touch.azimuthAngle(in: nil)
        let altitude = touch.altitudeAngle
        
        //touchLog.log(phase, nextXY, radius)
        
        let item = makeTouchCanvasItem(touch.hash, force, radius, nextXY, phase, azimuth, altitude, Visitor(0, .canvas))
        
        buffer.addItem(item, bufferType: .local)
        
        Task {
            await canvas.peers.sendItem(.touchFrame) {
                do {
                    return try JSONEncoder().encode(item)
                } catch {
                    print(error)
                    return nil
                }
            }
        }
    }
    
    public func makeTouchCanvasItem(_ key     : Int,
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
    func flushTouches(_ touchRepeat: Bool) -> Bool {
        
        if buffer.isEmpty,
           touchRepeat,
           repeatLastItem != nil {
            // finger is stationary repeat last movement
            // don't update touchCubic.addPointRadius
            touchCubic.drawPoints(canvas.touchDraw.drawPoint)
            
        } else {
            let state = buffer.flushBuf()
            isDone = (state == .done)
        }
        return isDone
    }
}

extension TouchCanvasBuffer: CircleBufferDelegate {
    public typealias Item = TouchCanvasItem

    public func flushItem<Item>(_ item: Item, _ type: BufferType) -> FlushState {
        guard let item = item as? TouchCanvasItem else {
            print("Error: Not a TouchCanvasItem")
            return .continue
        }
        let radius = canvas.touchDraw.updateRadius(item)
        let point = item.cgPoint
        isDone = item.isDone()
        repeatLastItem = isDone ? nil : item
        
        touchCubic.addPointRadius(point, radius, isDone)
        touchCubic.drawPoints(canvas.touchDraw.drawPoint)
        
        return isDone ? .done : .continue
    }
}
