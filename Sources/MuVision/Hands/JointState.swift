// created by musesum on 1/20/24

import UIKit
import simd
import MuFlo

public class JointState {

    public var joint˚: Flo?
    public var floDraw˚: Flo?
    public var floMenu˚: Flo?
    public var chiral: Chiral!
    public var joint: JointEnum!
    public var pos = SIMD3<Float>.zero

    public var time = TimeInterval(0)
    public var timeBegin = TimeInterval(0)
    public var timeEnded = TimeInterval(0)
    public var taps = 0
    public var phase = UITouch.Phase.ended
    public var on = false
    public var active: Bool {
        phase.rawValue < 3 // .began, .moved, .stationary
    }

    /// hash should be the same between all devices during runtime
    public var hash: Int { chiral.rawValue * 1000 + joint.rawValue }

    /// distance between thumb and fingerTip to register a touch
    internal var touchBeganTheshold = Float(0.01)
    internal var touchEndedTheshold = Float(0.02)

    /// toggling on/off with other hand
    internal var otherTouching = false
    internal var otherTimeBegin = TimeInterval(0)
    internal var otherTimeEnded = TimeInterval(0)
    internal var tapThreshold = TimeInterval(0.33)

    func bindJoint(_ chiral: Chiral,
                   _ hand˚: Flo,
                   _ joint: JointEnum) -> Bool {

        self.chiral = chiral
        self.joint = joint

        joint˚ = hand˚.bind(joint.name) { flo,_ in
            self.updateJoint(flo)
            flo.activate([], from: flo)
        }
        if let joint˚ {
            joint˚.setExpr("state", self)
            updateJoint(joint˚)
            if self.on {
                DebugLog { P("🖐️ "+joint˚.path(3)+"(on: \(self.on))") }
            }
            return on
        } else {
            PrintLog("⁉️ JointFlo::updateJoint \(joint.name) not Found")
            return false
        }
    }
    func updateJoint(_ flo: Flo) {
        pos = flo.xyz
        time = flo.val("time") ?? 0
        phase = UITouch.Phase(rawValue: flo.intVal("phase") ?? 0)!
        on = flo.boolVal("on")
    }

    /// thumb finger tip as continuous controller or brush
    func updateThumbTip(_ thumbTip: JointState) -> Int {

        // thumb tip touching another joint
        if thumbTip.active, !self.active {
            return 0
        }
        let distance = distance(thumbTip.pos, pos)
        let touching = distance < (active ? touchEndedTheshold : touchBeganTheshold)
        let oldPhase = phase.rawValue

        if  touching {
            if active { updatePhase(.moved, "👍🔹", interval: 0.5) }
            else      { updatePhase(.began, "👍🟢", interval: 0.0) }
        } else {
            if active { updatePhase(.ended, "👍♦️", interval: 0.0) }
        } 
        return touching ? 1 : 0

        func updatePhase(_ phase: UITouch.Phase,
                         _ color: String,
                         interval: TimeInterval) {

            switch phase {

            case .began:

                timeBegin = Date().timeIntervalSince1970
                let deltaTime = timeBegin - timeEnded
                if deltaTime > tapThreshold {
                    taps = 0
                }

            case .ended:

                timeEnded = Date().timeIntervalSince1970
                let deltaTime = timeEnded - timeBegin
                if deltaTime < tapThreshold {
                    taps += 1
                } else {
                    taps = 0
                }
            default: break
            }
            /// recalibrate range after triple
            let setOps: SetOps = taps > 2 ? [.fire, .ranging] : [.fire]
            thumbTip.updateFlo(phase, setOps)
            self.updateFlo(phase, setOps)


            TimeLog("\(#function).\(hash)", interval: interval) {
                let path = "\(self.chiral?.icon ?? "") \(self.joint˚?.path(3) ?? "??")".pad(18)
                let mine = "\(path) \(self.pos.digits(-2))"

                if self.taps > 2 {
                    var ranges = ""
                    if self.taps > 2,
                       let exprs = self.joint˚?.exprs,
                       let x = exprs.nameAny["x"] as? Scalar,
                       let y = exprs.nameAny["y"] as? Scalar,
                       let z = exprs.nameAny["z"] as? Scalar
                    {
                        let xRange = "\(x.minim.digits(2))…\(x.maxim.digits(2))"
                        let yRange = "\(y.minim.digits(2))…\(y.maxim.digits(2))"
                        let zRange = "\(z.minim.digits(2))…\(z.maxim.digits(2))"
                        ranges = "🔳 (\(xRange), \(yRange), \(zRange))"
                    }

                    print("\(color) \(mine) \(ranges)")
                } else {
                    let phase = "👐phase \(oldPhase) => \(phase.rawValue) taps \(self.taps) \(self.taps > 2 ? "🔳" : "")"
                    let tip =  "∆ thumbTip =>\(distance.digits(3)) \(phase)"
                    print("\(color) \(mine) \(tip)")

                }
            }
        }
    }

    func updatePos(_ pos: SIMD3<Float>) async {
        self.pos = pos
        updateFlo(phase,.sneak)
    }

    func updateFlo(_ phase: UITouch.Phase,
                   time: TimeInterval = Date().timeIntervalSince1970,
                   _ setOps: SetOps) {
        self.phase = phase
        self.time = time
        let nameDoubles: [(String,Double)] = [
            ("x",     Double(pos.x)),
            ("y",     Double(pos.y)),
            ("z",     Double(pos.z)),
            ("time",  Double(time )),
            ("phase", Double(phase.rawValue)),
            ("joint", Double(joint.rawValue))]
        if let joint˚ {
            joint˚.exprs?.setFromAny(nameDoubles, setOps, Visitor(0))
            if setOps == .fire {
                joint˚.activate([], from: joint˚)
            }
        }
    }
}
