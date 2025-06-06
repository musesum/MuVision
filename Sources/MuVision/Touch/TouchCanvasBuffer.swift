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

    private var timeLag: TimeInterval = 0.2
    private var timeNext: TimeInterval?

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
        
        let item = TouchCanvasItem(repeatLastItem, joint.hash, force, radius, nextXY, phase, azimuth, altitude, Visitor(0, .canvas))

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
        
        let item = TouchCanvasItem(repeatLastItem, touch.hash, force, radius, nextXY, phase, azimuth, altitude, Visitor(0, .canvas))

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
    
    
    func flushTouches(_ touchRepeat: Bool) -> Bool {
        
        if buffer.isEmpty,
           touchRepeat,
           repeatLastItem != nil {
            // finger is stationary repeat last movement
            // don't update touchCubic.addPointRadius
            touchCubic.drawPoints(canvas.touchDraw.drawPoint)
            
        } else {
            let state = buffer.flushBuf()
            switch state {
            case .done:
                isDone = true
            case .wait:
                if touchRepeat,
                   repeatLastItem != nil {
                    touchCubic.drawPoints(canvas.touchDraw.drawPoint)
                }
            case .continue: break

            }
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
        let timeNow = Date().timeIntervalSince1970

        if type == .remote {
            // already waiting?
            let timeNext = timeNext ?? timeLag + item.time
            if timeNow < timeNext {
                return .wait // try later
            } else {
                self.timeNext = nil // process now
            }
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

