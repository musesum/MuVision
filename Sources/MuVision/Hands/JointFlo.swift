// created by musesum on 1/20/24

import Foundation
import UIKit
import simd
import MuFlo

public protocol TouchCanvasDelegate {
    func handBegin(_ jointFlo: JointFlo)
    func handUpdate(_ jointFlo: JointFlo)
}

public class JointFlo {

    var flo˚: Flo?
    var on = false  // is this tracked?
    var touching = false
    var timeBegin = TimeInterval(0)
    var timeEnded = TimeInterval(0)

    /// distance between thumb and fingerTip to register a touch
    var touchTheshold = Float(0.015)

    /// sometimes a tracker skips a joint, so
    /// that is still within tapThreshold (false negative)
    var touchRelease = TimeInterval(0.10)
    var touchTimer = Timer()

    var tapThreshold = TimeInterval(0.33)

    var chiral: Chiral!
    var joint: JointEnum!

    public var pos = SIMD3<Float>.zero
    public var time = TimeInterval(0)
    public var phase = UITouch.Phase.ended

    /// hash should be the same between all devices during runtime
    public var hash: Int { chiral.rawValue * 1000 + joint.rawValue }

    func parseJoint(_ chiral: Chiral, _ hand˚: Flo, _ joint: JointEnum) {

        self.chiral = chiral
        self.joint = joint

        flo˚ = hand˚.bind(joint.name) { val,_ in
            self.pos = val.xyz
            self.time  = val.component(named: "time") as? Double ?? 0
            self.phase = val.component(named: "phase") as? UITouch.Phase ?? .began
        }
        if flo˚ == nil { err("flo˚") }
        func err(_ msg: String) {
            print("⁉️ JointFlo::\(#function) \(flo˚?.path() ?? "").\(msg) not Found")
        }
    }
    /// index finger tip toogles on/off
    func updateIndexTip(_ indexTip: JointFlo) -> Int {
        let d = distance(indexTip.pos, pos)
        if  d < touchTheshold {
            if !touching {
                touching = true
                timeBegin = Date().timeIntervalSince1970
            }
        } else {
            if touching {
                touching = false
                timeEnded = Date().timeIntervalSince1970
                let timeDelta = timeEnded - timeBegin
                if timeDelta < tapThreshold {
                    on = !on
                    log(on ? "❇️" : "🅾️")
                    return 1
                }
            }
        }
        return 0
        
        func log(_ prefix: String) {

            let path = "\(chiral.name).\(flo˚?.path() ?? "??")".pad(18)
            let mine = path + pos.script(-2)
            let index = "indexTip\(indexTip.pos.script(-2))"
            let label = "\(prefix)\(mine) ∆ \(index) => \(d.digits(3)) "
            MuLog.RunLog(label, interval: 0) {}
        }
    }
    /// thumb finger tip as continuos controller or brush
    func updateThumbTip(_ thumbTip: JointFlo) -> Int {

        let d = distance(thumbTip.pos, pos)
        if d < touchTheshold {
            switch phase {
            case .began: updateFlo(.moved); log("🔵")
            case .moved: updateFlo(.moved); log("🔵")
            default:     updateFlo(.began); log("🟢")
            }
        } else {
            switch phase {
            case .began: updateFlo(.ended); log("🔴")
            case .moved: updateFlo(.ended); log("🔴")
            default:     return 0
            }
        }
        return 1

        func log(_ prefix: String) {
            let path = "\(chiral.name).\(flo˚?.path() ?? "??")".pad(18)
            let mine = path + self.pos.script(-2)
            let thumb = "thumbTip\(thumbTip.pos.script(-2))"
            let label = "\(prefix) \(mine) ∆ \(thumb) => \(d.digits(3)) "
            MuLog.RunLog(label, interval: 0) { }
        }
    }

    func updatePos(_ pos: SIMD3<Float>) async {
        self.pos = pos
        updateFlo(phase,.sneak)
    }

    func updateFlo(_ phase: UITouch.Phase,
                   time: TimeInterval = Date().timeIntervalSince1970,
                   _ options: FloSetOps = .activate) {
        self.phase = phase
        self.time = time
        let nameDoubles: [(String,Double)] = [
            ("x"    , Double(pos.x)),
            ("y"    , Double(pos.y)),
            ("z"    , Double(pos.z)),
            ("time" , Double(time )),
            ("phase", Double(phase.rawValue)),
            ("joint", Double(joint.rawValue))]
        if let flo˚ {
            flo˚.setDoubles(nameDoubles)
            if options == .activate {
                flo˚.activate(Visitor(0))
            }
        }
    }
}


