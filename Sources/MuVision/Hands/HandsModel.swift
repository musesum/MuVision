// created by musesum on 1/18/24

import ARKit
import MuFlo

open class HandsModel {

    @Published var updated: Bool = false

    public let handsFlo = LeftRight<HandPose>(HandPose(), HandPose())

    public init(_ touchCanvas: TouchCanvas,
                _ rootFlo: Flo) {

        let handFlo˚ = rootFlo.bind("hand")
        if handFlo˚.bound {
            handsFlo.left .bindChiral(.left,  handFlo˚.bind("left" ))
            handsFlo.right.bindChiral(.right, handFlo˚.bind("right"))
        }
        handsFlo.left .parseDraw(touchCanvas, .left,  rootFlo)
        handsFlo.right.parseDraw(touchCanvas, .right, rootFlo)

        // print(rootHandFlo?.scriptFull)

        self.handsFlo.left .trackAllJoints(on: true)
        self.handsFlo.right.trackAllJoints(on: true)
    }
}
