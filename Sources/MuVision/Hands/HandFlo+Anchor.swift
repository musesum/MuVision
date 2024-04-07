// created by musesum on 3/16/24

#if os(visionOS)

import ARKit
import MuFlo

extension HandFlo {

    func updateAnchor(_ anchor: HandAnchor,
                      _ otherHand: HandFlo) async {

        guard let skeleton = anchor.handSkeleton else { return err("skeleton")}

        let transform = anchor.originFromAnchorTransform
        for (jointEnum, jointFlo) in joints {
            if jointFlo.on,
               let arName = jointEnum.arJoint {

                let arJoint = skeleton.joint(arName)
                let pos = matrix_multiply(transform, arJoint.anchorFromJointTransform).columns.3.xyz

                await jointFlo.updatePos(pos)
            }
        }
        updateThumbIndex(otherHand)

        MuLog.Log("HandFlo", interval: 2.0) {
            var msg = ""
            for (jointEnum, jointFlo) in self.joints {
                if jointFlo.on {
                    msg += jointEnum.name + jointFlo.pos.script(-2) + " "
                }
            }
            if !msg.isEmpty {
                print("\n🖐️ " + msg + "\n")
            }
        }

        func err(_ msg: String) { print("⁉️ HandFlo::\(#function) err: \(msg)") }
    }
    
}

#endif
