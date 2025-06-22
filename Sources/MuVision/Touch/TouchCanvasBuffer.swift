//  created by musesum on 8/22/23.

import UIKit
import MuFlo
import MuPeers

open class TouchCanvasBuffer {
    let id = Visitor.nextId()
    // repeat last touch until isDone
    private var repeatLastItem: TouchCanvasItem?
    
    // each finger or brush gets its own double buffer
    public let buffer = TimedBuffer<TouchCanvasItem>(capacity: 5, internalLoop: false)
    private var indexNow = 0
    private var canvas: TouchCanvas
    private var isDone = false
    private var touchCubic = TouchCubic()
    private var touchLog = TouchLog()

    deinit {
        Panic.remove(id)
    }
    public init(_ touch: UITouch,
                _ canvas: TouchCanvas) {
        
        self.canvas = canvas
        buffer.delegate = self
        buffer.timeLag = 0.2
        buffer.autoAdjustLag = true
        buffer.catchUpRate = 0.9
        buffer.maxBacklog = 0.4 // 2x packet delay
        addTouchItem(touch)
        Panic.add(id,self)
    }
    
    public init(_ item: TouchCanvasItem,
                _ canvas: TouchCanvas) {

        self.canvas = canvas
        buffer.delegate = self
        buffer.timeLag = 0.2
        buffer.autoAdjustLag = true
        buffer.catchUpRate = 0.9
        buffer.maxBacklog = 0.4 // 2x packet delay
        buffer.addItem(item, bufType: .remoteBuf)
        Panic.add(id,self)
    }
    
    public init(_ joint: JointState,
                _ canvas: TouchCanvas) {
        
        self.canvas = canvas
        buffer.delegate = self
        buffer.timeLag = 0.2
        buffer.autoAdjustLag = true
        buffer.catchUpRate = 0.9
        buffer.maxBacklog = 0.4 // 2x packet delay
        addTouchHand(joint)
        Panic.add(id,self)
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

        buffer.addItem(item, bufType: .localBuf)
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

        buffer.addItem(item, bufType: .localBuf)
        
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
            case .doneBuf:
                isDone = true
            case .waitBuf:
                if touchRepeat,
                   repeatLastItem != nil {
                    touchCubic.drawPoints(canvas.touchDraw.drawPoint)
                }
            case .nextBuf: break

            }
        }
        return isDone
    }
}

extension TouchCanvasBuffer: TimedBufferDelegate {
    public typealias Item = TouchCanvasItem

    public func flushItem<Item>(_ item: Item, _ type: BufType) -> BufState {
        guard let item = item as? TouchCanvasItem else {
            print("Error: Not a TouchCanvasItem")
            return .nextBuf
        }
        // Timing logic is now handled in TimedBuffer.flushBuf()
        
        let radius = canvas.touchDraw.updateRadius(item)
        let point = item.cgPoint
        isDone = item.isDone
        repeatLastItem = isDone ? nil : item
        
        touchCubic.addPointRadius(point, radius, isDone)
        touchCubic.drawPoints(canvas.touchDraw.drawPoint)
        
        return isDone ? .doneBuf : .nextBuf
    }
}

extension TouchCanvasBuffer: PanicReset {
    public func reset() {
        buffer.reset() // assuming reset() empties the buffer; replace with buffer.clear() if that is the correct API
        repeatLastItem = nil
        indexNow = 0
        isDone = false
        touchCubic = TouchCubic()
        touchLog = TouchLog()
    }
}
