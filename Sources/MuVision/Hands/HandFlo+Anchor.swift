// created by musesum on 3/16/24

#if os(visionOS)

import ARKit
import MuFlo

extension HandPose {

    func updateAnchor(_ anchor: HandAnchor,
                      _ otherHand: HandPose) async {

        guard let skeleton = anchor.handSkeleton else { return err("skeleton")}

        let transform = anchor.originFromAnchorTransform
        for (jointEnum, jointState) in joints {
            if jointState.on,
               let arName = jointEnum.arJoint {

                let arJoint = skeleton.joint(arName)
                let pos = matrix_multiply(transform, arJoint.anchorFromJointTransform).columns.3.xyz

                await jointState.updatePos(pos)
            }
        }
        updateThumbIndex()
        updateOtherHand(otherHand)

        TimeLog(#function, interval: 2.0) {
            var msg = ""
            for (jointEnum, jointState) in self.joints {
                if jointState.on {
                    msg += jointEnum.name + jointState.pos.digits(-2) + " "
                }
            }
            if !msg.isEmpty {
                print("\n🖐️ " + msg + "\n")
            }
        }

        func err(_ msg: String) { PrintLog("⁉️ HandFlo::parseAnchor err: \(msg)") }
    }
    
}

#endif
