// created by musesum on 1/20/24

import UIKit
import simd
import MuFlo

public class JointState {

    public var flo˚: Flo?
    public var chiral: Chiral!
    public var joint: JointEnum!
    public var pos = SIMD3<Float>.zero

    public var time = TimeInterval(0)
    public var timeBegin = TimeInterval(0)
    public var timeEnded = TimeInterval(0)

    public var phase = UITouch.Phase.ended
    public var on = false

    /// hash should be the same between all devices during runtime
    public var hash: Int { chiral.rawValue * 1000 + joint.rawValue }

    /// distance between thumb and fingerTip to register a touch
    internal var touchTheshold = Float(0.015)

    /// toggling on/off with other hand
    internal var otherTouching = false
    internal var otherTimeBegin = TimeInterval(0)
    internal var otherTimeEnded = TimeInterval(0)
    internal var tapThreshold = TimeInterval(0.33)

    func parseJoint(_ chiral: Chiral,
                    _ hand˚: Flo,
                    _ joint: JointEnum) -> Bool {

        self.chiral = chiral
        self.joint = joint

        flo˚ = hand˚.bind(joint.name) { flo,_ in
            self.updateJoint(flo)
            flo.activate(from:flo)
        }
        if let flo˚ {
            flo˚.setExpr("state", self)
            updateJoint(flo˚)
            print(flo˚.path(3)+"(on: \(on))")
            return on
        } else {
            PrintLog("⁉️ JointFlo::parseJoint \(joint.name) not Found")
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

        let distance = distance(thumbTip.pos, pos)
        let touching = distance < touchTheshold
        let oldPhase = phase.rawValue
        let active = phase.rawValue < 3

        if  touching {
            if active { updatePhase(.moved, "👍🔹", interval: 0.3) }
            else      { updatePhase(.began, "👍🟢", interval: 0) }
        } else {
            if active { updatePhase(.ended, "👍♦️", interval: 0) }
        }
        return touching ? 1 : 0

        func updatePhase(_ phase: UITouch.Phase,
                         _ color: String,
                         interval: TimeInterval) {

            updateFlo(phase)

            TimeLog("\(#function).\(hash)", interval: interval) {
                let path = "\(self.chiral?.icon ?? "") \(self.flo˚?.path(3) ?? "??")".pad(18)
                let mine = path + self.pos.digits(-2)
                let thumb = "thumbTip\(thumbTip.pos.digits(-2))"
                let hash = "👐\(self.hash) \(oldPhase) => \(phase.rawValue)"
                let title = "\(color) \(mine) ∆ \(thumb) => \(distance.digits(3)) \(hash)"
                print(title)
            }
        }
    }

    func updatePos(_ pos: SIMD3<Float>) async {
        self.pos = pos
        updateFlo(phase,.sneak)
    }

    func updateFlo(_ phase: UITouch.Phase,
                   time: TimeInterval = Date().timeIntervalSince1970,
                   _ options: SetOptions = .fire) {
        self.phase = phase
        self.time = time
        let nameDoubles: [(String,Double)] = [
            ("x",     Double(pos.x)),
            ("y",     Double(pos.y)),
            ("z",     Double(pos.z)),
            ("time",  Double(time )),
            ("phase", Double(phase.rawValue)),
            ("joint", Double(joint.rawValue))]
        if let flo˚ {
            flo˚.setDoubles(nameDoubles)
            if options == .fire {
                flo˚.activate(from: flo˚)
            }
        }
    }
}
