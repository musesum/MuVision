// created by musesum on 3/19/24

import UIKit
import simd
import MuFlo

public class JointCanvasFlo: JointFlo {

    var touchCanvas: TouchCanvasDelegate?
    
    func parseCanvas(_ touchCanvas: TouchCanvasDelegate,
                     _ chiral: Chiral,
                     _ parent˚: Flo) {

        self.touchCanvas = touchCanvas
        self.joint = .touch
        self.chiral = chiral

        flo˚ = parent˚.bind(joint.name) { val,_ in
            self.pos = val.xyz
            self.time  = val.component(named: "time" ) as? Double ?? 0
            
            let joint = val.component(named: "joint") as? Double ?? 0
            self.joint = JointEnum(rawValue: Int(joint))

            self.phase = val.component(named: "phase") as? UITouch.Phase ?? .began

            switch self.phase {
            case .began: self.touchCanvas?.handBegin(self)
            default:     self.touchCanvas?.handUpdate(self)
            }
        }
        if flo˚ == nil { err("flo˚") }
        func err(_ msg: String) {
            print("⁉️ JointCanvasFlo::\(#function) \(flo˚?.path() ?? "").\(msg) not Found")
        }
    }

}
