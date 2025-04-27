// created by musesum on 3/19/24

import UIKit
import simd
import MuFlo

public class JointDrawState: JointState {

    var touchCanvas: TouchCanvas?

    func bindHand(_ hand˚: Flo,
                  _ touchCanvas: TouchCanvas,
                  _ chiral: Chiral) {

        self.touchCanvas = touchCanvas
        self.joint = .touching
        self.chiral = chiral

        bindFloDraw(hand˚,touchCanvas)
        bindFloMenu(hand˚,touchCanvas)
    }
    func bindFloDraw(_ hand˚: Flo,
                     _ touchCanvas: TouchCanvas) {

        floDraw˚ = hand˚.bind("draw") { flo, visit in

            guard let from = visit.from else { return err("visit.from == nil") }
            guard let joint = from.getExpr("state") as? JointState else { return err("not a JointState") }
            guard let touchCanvas = self.touchCanvas else { return err("touchCanvas == nil") }

            TimeLog("👐 from", interval: 4) { P("👐 from: \(from.path(3)) hash: \(joint.hash)") }

            switch self.phase {
            case .began: touchCanvas.beginJointState(joint)
            default:     touchCanvas.updateJointState(joint)
            }
        }
        func err(_ msg: String)  {
            DebugLog { P("⁉️ \(#function) \(msg)") }
        }
    }
    /// Intended to bring back a dismissed menu, this has been deferred
    ///
    func bindFloMenu(_ hand˚: Flo,
                     _ touchCanvas: TouchCanvas) {
        #if false
        floMenu˚ = hand˚.bind("menu") { flo, visit in

            guard let from = visit.from else { return err("visit.from == nil") }
            guard let joint = from.getExpr("state") as? JointState else { return err("not a JointState") }

            if self.phase == .ended,
               let immersive = touchCanvas.immersiveDelegate
            {
                DebugLog { P("👐👆 from: \(from.path(3)) hash: \(joint.hash) taps: \(joint.taps)") }
                if joint.taps > 0 {
                    Task { @MainActor in
                        await immersive.reshowMenu()
                    }
                }
            }
        }
        func err(_ msg: String) {
            DebugLog { P("⁉️ \(#function) \(msg)") }
        }
        #endif

    }

}
