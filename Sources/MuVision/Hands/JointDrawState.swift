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

        flo˚ = hand˚.bind("draw") { flo, visit in

            guard let from = visit.from else { return err("visit.from == nil") }
            guard let joint = from.getExpr("state") as? JointState else { return err("not a JointState") }
            guard let touchCanvas = self.touchCanvas else { return err("touchCanvas == nil") }

            TimeLog("👐 from", interval: 4) { P("👐 from: \(from.path(3)) hash: \(joint.hash)") }

            switch self.phase {
            case .began: touchCanvas.beginJointState(joint)
            default:     touchCanvas.updateJointState(joint)
            }
        }
        if flo˚ == nil { err(flo˚?.path() ?? "flo˚ not found") }

        func err(_ msg: String) {
            let title = "⁉️ JointCanvasState::bindHand"
            DebugLog { P("\(title) \(msg)") }
        }
    }

}
