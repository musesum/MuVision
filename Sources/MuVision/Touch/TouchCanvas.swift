//  created by musesum on 2/5/19.

import UIKit
import MuFlo
import MuPeer

public protocol TouchCanvasDelegate {
    func beginHand(_ jointState: JointState)
    func updateHand(_ jointState: JointState)
}

public typealias TouchDrawPoint = ((CGPoint, CGFloat)->())
public typealias TouchDrawRadius = ((TouchCanvasItem)->(CGFloat))

open class TouchCanvas {

    static public let shared = TouchCanvas()
    static var touchRepeat = true
    static var touchBuffers = [Int: TouchCanvasBuffer]()


    public init() {
        PeersController.shared.peersDelegates.append(self)
    }
    deinit {
        PeersController.shared.remove(peersDelegate: self)
    }
}


// ARKit visionOS Handpose
extension TouchCanvas: TouchCanvasDelegate {

    public func beginHand(_ jointState: JointState) {

        TouchCanvas.touchBuffers[jointState.hash] = TouchCanvasBuffer(jointState, self)
        // DebugLog { P("beginHand 👐\(jointState.hash)") }
    }

    public func updateHand(_ jointState: JointState) {
        if let touchBuffer = TouchCanvas.touchBuffers[jointState.hash] {
            touchBuffer.addTouchHand(jointState)
            // DebugLog { P("👐 updateHand hash: \(jointState.hash)") }
        } else {
            beginHand(jointState)
            // DebugLog { P("👐 updateHand ⁉️ hash\(jointState.hash)") }
        }
    }
}

// UIKit Touches
extension TouchCanvas: TouchProtocol {

    public func beginTouch(_ touch: UITouch) -> Bool {
        TouchCanvas.touchBuffers[touch.hash] = TouchCanvasBuffer(touch, self)
        return true
    }
    public func updateTouch(_ touch: UITouch) -> Bool {
        if let touchBuffer = TouchCanvas.touchBuffers[touch.hash] {
            touchBuffer.addTouchItem(touch)
            return true
        }
        return false
    }
}

extension TouchCanvas {
    

    public func remoteItem(_ item: TouchCanvasItem) {

        if let touchBuffer = TouchCanvas.touchBuffers[item.key] {
            touchBuffer.addTouchCanvasItem(item)
        } else {
            TouchCanvas.touchBuffers[item.key] = TouchCanvasBuffer(item, self)
        }
    }
    public static func flushTouchCanvas() {
        var removeKeys = [Int]()
        for (key, buf) in touchBuffers {
            let isDone = buf.flushTouches(touchRepeat)
            if isDone { removeKeys.append(key) }
        }
        for key in removeKeys {
            touchBuffers.removeValue(forKey: key)
        }
    }
}


public protocol TouchProtocol {
    func beginTouch(_ touch: UITouch) -> Bool
    func updateTouch(_ touch: UITouch) -> Bool
}
