// created by musesum on 1/18/24

import ARKit
import MuFlo

open class HandsModel {

    @Published var updated: Bool = false
    
    public let handsFlo = LeftRight<HandFlo>(HandFlo(), HandFlo())
    
    public init(_ touchCanvas: TouchCanvasDelegate,
                _ rootFlo: Flo,
                _ archive: FloArchive) {

        MuHand.parseFlo(rootFlo, "model.hand")
        let rootHandFlo = rootFlo.bind("model.hand")
        handsFlo.left.parseHand(.left, rootHandFlo.bind("left"))
        handsFlo.right.parseHand(.right, rootHandFlo.bind("right"))

        handsFlo.left.parseCanvas(touchCanvas, .left, rootFlo)
        handsFlo.right.parseCanvas(touchCanvas, .right, rootFlo)

        print(rootHandFlo.scriptFull)

        self.handsFlo.left.trackAllJoints(on: true)
        self.handsFlo.right.trackAllJoints(on: true)
    }
}
