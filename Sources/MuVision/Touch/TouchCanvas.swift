//  created by musesum on 2/5/19.

import UIKit
import MuFlo
import MuPeer

public typealias TouchDrawPoint = ((CGPoint, CGFloat)->())
public typealias TouchDrawRadius = ((TouchCanvasItem)->(CGFloat))

@MainActor //_____
open class TouchCanvas: @unchecked Sendable {
    
    nonisolated(unsafe) static var touchBuffers = [Int: TouchCanvasBuffer]()
    let touchDraw: TouchDraw
    
    public static func flushTouchCanvas() {
        var removeKeys = [Int]()
        for (key, buf) in touchBuffers {
            let isDone = buf.flushTouches(/*touchRepeat*/ true) //....
            if isDone { removeKeys.append(key) }
        }
        for key in removeKeys {
            touchBuffers.removeValue(forKey: key)
        }
    }
    
    
    public init(_ touchDraw: TouchDraw) {
        self.touchDraw = touchDraw
        Peers.shared.delegates["TouchCanvas"] = self
    }
    deinit { Peers.shared.removeDelegate("TouchCanvas") }
    
    public func beginJointState(_ jointState: JointState) {
        TouchCanvas.touchBuffers[jointState.hash] = TouchCanvasBuffer(jointState, self)
        // DebugLog { P("beginJoint 👐\(jointState.hash)") }
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
@MainActor //_____
extension TouchCanvas { // + Touch
    
    public func beginTouch(_ touch: SendTouch) async -> Bool {
        await TouchCanvas.touchBuffers[touch.hash] = TouchCanvasBuffer(touch, self)
        return true
    }
    public func updateTouch(_ touch: SendTouch) async -> Bool {
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
@MainActor //_____
extension TouchCanvas: PeersDelegate {
    
    nonisolated public func didChange() {
    }
    
    nonisolated public func received(data: Data, viaStream: Bool) {
        
        let decoder = JSONDecoder()
        if let item = try? decoder.decode(TouchCanvasItem.self, from: data) {
            DispatchQueue.main.async {
                self.remoteItem(item)
            }
        }
    }
    
}
