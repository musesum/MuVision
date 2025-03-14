// created by musesum on 1/18/24

import ARKit
import MuFlo

open class HandsModel {

    @Published var updated: Bool = false

    public let handsFlo = LeftRight<HandPose>(HandPose(), HandPose())

    public init(_ touchCanvas: TouchCanvas,
                _ rootFlo: Flo) {

        let handFlo˚ = rootFlo.bind("model.hand")
        if handFlo˚.bound {
            handsFlo.left .updateHand(.left,  handFlo˚.bind("left" ))
            handsFlo.right.updateHand(.right, handFlo˚.bind("right"))
        }
        handsFlo.left .parseCanvas(touchCanvas, .left,  rootFlo)
        handsFlo.right.parseCanvas(touchCanvas, .right, rootFlo)

        // print(rootHandFlo?.scriptFull)

        self.handsFlo.left .trackAllJoints(on: true)
        self.handsFlo.right.trackAllJoints(on: true)
    }
}
