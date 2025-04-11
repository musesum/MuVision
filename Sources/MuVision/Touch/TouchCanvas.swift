//  created by musesum on 2/5/19.

import UIKit
import MuFlo
import MuPeer

public typealias TouchDrawPoint = ((CGPoint, CGFloat)->())
public typealias TouchDrawRadius = ((TouchCanvasItem)->(CGFloat))

public protocol ImmersionDelegate {
    func updateImmersion(_ immersive: Bool) async
    func reshowMenu() async
}


open class TouchCanvas {

    static public let shared = TouchCanvas()
    
    static var touchRepeat = true
    static var touchBuffers = [Int: TouchCanvasBuffer]()

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

    public var immersiveDelegate: ImmersionDelegate?
    public var immersive = false

    public init() { PeersController.shared.peersDelegates.append(self) }
    deinit { PeersController.shared.remove(peersDelegate: self) }

    public func beginJointState(_ jointState: JointState) {
        TouchCanvas.touchBuffers[jointState.hash] = TouchCanvasBuffer(jointState, self)
        //DebugLog { P("👐 beginJoint \(jointState.joint˚?.path(2) ?? "??")") }
    }

    public func updateJointState(_ jointState: JointState) {
        if let touchBuffer = TouchCanvas.touchBuffers[jointState.hash] {
            touchBuffer.addTouchHand(jointState)
            // DebugLog { P("👐 updateHand hash: \(jointState.hash)") }
        } else {
            beginJointState(jointState)
            // DebugLog { P("👐 updateHand ⁉️ hash\(jointState.hash)") }
        }
    }
}

extension TouchCanvas { // + Touch

    public func beginTouch(_ touch: UITouch) -> Bool {
        if immersive { return true }
        TouchCanvas.touchBuffers[touch.hash] = TouchCanvasBuffer(touch, self)
        return true
    }
    public func updateTouch(_ touch: UITouch) -> Bool {
        if immersive { return true }
        if let touchBuffer = TouchCanvas.touchBuffers[touch.hash] {
            touchBuffer.addTouchItem(touch)
            return true
        }
        return false
    }

    public func remoteItem(_ item: TouchCanvasItem) {

        if let touchBuffer = TouchCanvas.touchBuffers[item.key] {
            touchBuffer.addTouchCanvasItem(item)
        } else {
            TouchCanvas.touchBuffers[item.key] = TouchCanvasBuffer(item, self)
        }
    }

}

