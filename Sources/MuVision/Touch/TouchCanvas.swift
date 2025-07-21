//  created by musesum on 2/5/19.

import UIKit
import MuFlo
import MuPeers

public typealias TouchDrawPoint = ((CGPoint, CGFloat)->())
public typealias TouchDrawRadius = ((TouchCanvasItem)->(CGFloat))

open class TouchCanvas: @unchecked Sendable {
    
    var touchRepeat = true
    var touchBuffers = [Int: TouchCanvasBuffer]()

    public func flushTouchCanvas() {
        var removeKeys = [Int]()
        for (key, buf) in touchBuffers {
            let isDone = buf.flushTouches(touchRepeat)
            if isDone { removeKeys.append(key) }
        }
        for key in removeKeys {
            touchBuffers.removeValue(forKey: key)
        }
    }
    
    let touchDraw: TouchDraw
    public let peers: Peers
    public var immersive = false

    public init(_ touchDraw: TouchDraw,
                _ peers: Peers) {
        self.touchDraw = touchDraw
        self.peers = peers
        peers.setDelegate(self, for: .touchFrame)
    }

    public func beginJointState(_ jointState: JointState) {
        touchBuffers[jointState.hash] = TouchCanvasBuffer(jointState, self)
        //DebugLog { P("👐 beginJoint \(jointState.joint˚?.path(2) ?? "??")") }
    }

    public func updateJointState(_ jointState: JointState) {
        if let touchBuffer = touchBuffers[jointState.hash] {
            touchBuffer.addTouchHand(jointState)
            // DebugLog { P("👐 updateHand hash: \(jointState.hash)") }
        } else {
            beginJointState(jointState)
            // DebugLog { P("👐 updateHand ⁉️ hash\(jointState.hash)") }
        }
    }
}

extension TouchCanvas { // + TouchData

    public func beginTouch(_ touchData: TouchData) {
        if immersive { return }

        touchBuffers[touchData.key] = TouchCanvasBuffer(touchData, self)
    }

    public func updateTouch(_ touchData: TouchData) {
        if immersive { return }
        if let touchBuffer = touchBuffers[touchData.key] {
            touchBuffer.addTouchItem(touchData)
        }
    }
    public func remoteItem(_ item: TouchCanvasItem) {
        if let touchBuffer = touchBuffers[item.key] {
            touchBuffer.buffer.addItem(item, bufType: .remoteBuf)
        } else {
            touchBuffers[item.key] = TouchCanvasBuffer(item, self)
        }
    }
}


