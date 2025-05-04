// created by musesum on 8/20/24
import UIKit
import simd
import MuFlo

/// toggle on/off
extension JointState {

    /// index finger tip of other hand toogles on/off
    /// with a quick tap on thos joint
    func updateOtherHandIndexTip(_ indexTip: JointState) -> Int {

        let distance = distance(indexTip.pos, pos)

        if  distance < touchBeganTheshold {
            if !otherTouching {
                otherTouching = true
                otherTimeBegin = Date().timeIntervalSince1970
            }
        } else if distance > touchEndedTheshold {
            if otherTouching {
                otherTouching = false
                otherTimeEnded = Date().timeIntervalSince1970
                let timeDelta = otherTimeEnded - otherTimeBegin
                if timeDelta < tapThreshold {
                    return 1
                }
            }
        }
        func toggleOnOff() {
            on = !on

            TimeLog(#function+"\(hash)", log)
            func log() {
                let prefix = (on ? "❇️" : "🅾️")
                let path = "\(chiral.name).\(joint˚?.path() ?? "??")".pad(18)
                let mine = path + pos.digits(-2)
                let index = "indexTip\(indexTip.pos.digits(-2))"
                let label = "\(prefix)\(mine) ∆ \(index) => \(distance.digits(3)) "
                print(label)
            }

        }
        return 0
    }
}
