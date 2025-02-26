// created by musesum on 3/19/24

import UIKit
import simd
import MuFlo

public class JointCanvasState: JointState {

    var touchCanvas: TouchCanvasDelegate?
    
    func parseCanvas(_ touchCanvas: TouchCanvasDelegate,
                     _ chiral: Chiral,
                     _ parent˚: Flo) {

        self.touchCanvas = touchCanvas
        self.joint = .touching
        self.chiral = chiral

        flo˚ = parent˚.bind("touching") { flo, visit in

            guard let from = visit.from else { return err("visit.from == nil") }
            guard let joint = from.getExpr("state") as? JointState else { return err("any is not a JointState") }

            DebugLog { P("👐 parseCanvas from: \(from.path(3)) hash: \(joint.hash)") }

            switch self.phase {
            case .began: self.touchCanvas?.beginHand(joint)
            default:     self.touchCanvas?.updateHand(joint)
            }
        }
        if flo˚ == nil { err(flo˚?.path() ?? "flo˚ not found") }

        func err(_ msg: String) {
            let title = "⁉️ JointCanvasState::parseCanvas"
            DebugLog { P("\(title) \(msg)") }
        }
    }

}
