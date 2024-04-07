// created by musesum on 1/22/24

import ARKit
import MuFlo

public enum TouchJointStatus { case nothing, newJoint, oldJoint }

public class HandFlo {

    var chiral: Chiral?
    public var joints     = [JointEnum: JointFlo]()
    public var touchIndex = [JointEnum]()
    public var touchThumb = [JointEnum]()

    // joints from arkit
    var thumbKnuc   = JointFlo()
    var thumbBase   = JointFlo()
    var thumbInter  = JointFlo()
    var thumbTip    = JointFlo()
    var indexMeta   = JointFlo()
    var indexKnuc   = JointFlo()
    var indexBase   = JointFlo()
    var indexInter  = JointFlo()
    var indexTip    = JointFlo()
    var middleMeta  = JointFlo()
    var middleKnuc  = JointFlo()
    var middleBase  = JointFlo()
    var middleInter = JointFlo()
    var middleTip   = JointFlo()
    var ringMeta    = JointFlo()
    var ringKnuc    = JointFlo()
    var ringBase    = JointFlo()
    var ringInter   = JointFlo()
    var ringTip     = JointFlo()
    var littleMeta  = JointFlo()
    var littleKnuc  = JointFlo()
    var littleBase  = JointFlo()
    var littleInter = JointFlo()
    var littleTip   = JointFlo()
    var wrist       = JointFlo()
    var forearm     = JointFlo()
    // plus an extra for drawing on canvas
    var canvas      = JointCanvasFlo()

    public init() {

        joints = [
            .thumbKnuc   : thumbKnuc   ,
            .thumbBase   : thumbBase   ,
            .thumbInter  : thumbInter  ,
            .thumbTip    : thumbTip    ,
            .indexMeta   : indexMeta   ,
            .indexKnuc   : indexKnuc   ,
            .indexBase   : indexBase   ,
            .indexInter  : indexInter  ,
            .indexTip    : indexTip    ,
            .middleMeta  : middleMeta  ,
            .middleKnuc  : middleKnuc  ,
            .middleBase  : middleBase  ,
            .middleInter : middleInter ,
            .middleTip   : middleTip   ,
            .ringMeta    : ringMeta    ,
            .ringKnuc    : ringKnuc    ,
            .ringBase    : ringBase    ,
            .ringInter   : ringInter   ,
            .ringTip     : ringTip     ,
            .littleMeta  : littleMeta  ,
            .littleKnuc  : littleKnuc  ,
            .littleBase  : littleBase  ,
            .littleInter : littleInter ,
            .littleTip   : littleTip   ,
            .wrist       : wrist       ,
            .forearm     : forearm     ,
        ]
        touchIndex = [
            .thumbKnuc   ,
            .thumbBase   ,
            .thumbInter  ,
            .thumbTip    ,
            .indexMeta   ,
            .indexKnuc   ,
            .indexBase   ,
            .indexInter  ,
            .indexTip    ,
            .middleMeta  ,
            .middleKnuc  ,
            .middleBase  ,
            .middleInter ,
            .middleTip   ,
            .ringMeta    ,
            .ringKnuc    ,
            .ringBase    ,
            .ringInter   ,
            .ringTip     ,
            .littleMeta  ,
            .littleKnuc  ,
            .littleBase  ,
            .littleInter ,
            .littleTip   ,
//            .wrist       ,
//            .forearm     ,
        ]

        touchThumb = [
            .indexTip  ,
            .middleTip ,
            .ringTip   ,
            .littleTip ,
        ]
    }
    public func parseHand(_ chiral: Chiral,
                          _ hand˚: Flo) {

        self.chiral = chiral
        for (jointEnum, jointFlo) in self.joints {
            jointFlo.parse(chiral, hand˚, jointEnum)
        }

    }
    public func parseCanvas(_ touchCanvas: TouchCanvasDelegate,
                            _ chiral: Chiral,
                            _ root˚: Flo) {

        let parent˚ = root˚.bind("sky")
        canvas.parseCanvas(touchCanvas, chiral, parent˚)
    }

    public func trackAllJoints(on: Bool) {
        for jointItem in joints.values {
            jointItem.on = on
        }
    }

    public func trackJoints(_ trackJoints: [JointEnum], on: Bool) {
        for trackJoint in trackJoints {
            if let jointItem = joints[trackJoint] {
                jointItem.on = on
            }
        }
    }

    public func updateThumbIndex(_ otherHand: HandFlo) {
        var thumbCount = 0
        for jointEnum in touchThumb {
            if let jointFlo = joints[jointEnum] {
                thumbCount += jointFlo.updateThumbTip(thumbTip)
            }
        }
        var indexCount = 0
        for jointEnum in otherHand.touchIndex {
            if let jointFlo = otherHand.joints[jointEnum] {
                indexCount += jointFlo.updateIndexTip(indexTip)
            }
        }
        if thumbCount + indexCount > 0 {
            var label = chiral == .left ? "✋" : "🤚"
            label += thumbCount > 0 ? "👍\(thumbCount)" : ""
            label += indexCount > 0 ? "👆\(indexCount)" : ""
            MuLog.RunLog(label, interval: 0) {}
        }
    }

}


