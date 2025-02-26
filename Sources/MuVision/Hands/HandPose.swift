// created by musesum on 1/22/24

import ARKit
import MuFlo

public enum TouchJointStatus { case nothing, newJoint, oldJoint }

public class HandPose {

    var chiral: Chiral?
    public var joints     = [JointEnum: JointState]()
    public var jointOn    = Set<JointEnum>()
    public var touchIndex = [JointEnum]()
    public var touchThumb = [JointEnum]()


    // joints from arkit
    var thumbKnuc   = JointState()
    var thumbBase   = JointState()
    var thumbInter  = JointState()
    var thumbTip    = JointState()
    var indexMeta   = JointState()
    var indexKnuc   = JointState()
    var indexBase   = JointState()
    var indexInter  = JointState()
    var indexTip    = JointState()
    var middleMeta  = JointState()
    var middleKnuc  = JointState()
    var middleBase  = JointState()
    var middleInter = JointState()
    var middleTip   = JointState()
    var ringMeta    = JointState()
    var ringKnuc    = JointState()
    var ringBase    = JointState()
    var ringInter   = JointState()
    var ringTip     = JointState()
    var littleMeta  = JointState()
    var littleKnuc  = JointState()
    var littleBase  = JointState()
    var littleInter = JointState()
    var littleTip   = JointState()
    var wrist       = JointState()
    var forearm     = JointState()
    // plus an extra for drawing on canvas
    var canvas      = JointCanvasState()

    public init() {

        joints = [
            .thumbKnuc   : thumbKnuc,   
            .thumbBase   : thumbBase,   
            .thumbInter  : thumbInter,  
            .thumbTip    : thumbTip,    
            .indexMeta   : indexMeta,   
            .indexKnuc   : indexKnuc,   
            .indexBase   : indexBase,   
            .indexInter  : indexInter,  
            .indexTip    : indexTip,    
            .middleMeta  : middleMeta,  
            .middleKnuc  : middleKnuc,  
            .middleBase  : middleBase,  
            .middleInter : middleInter, 
            .middleTip   : middleTip,   
            .ringMeta    : ringMeta,    
            .ringKnuc    : ringKnuc,    
            .ringBase    : ringBase,    
            .ringInter   : ringInter,   
            .ringTip     : ringTip,     
            .littleMeta  : littleMeta,  
            .littleKnuc  : littleKnuc,  
            .littleBase  : littleBase,  
            .littleInter : littleInter, 
            .littleTip   : littleTip,   
            .wrist       : wrist,       
            .forearm     : forearm,     
        ]
        touchIndex = [
            .thumbKnuc,   
            .thumbBase,   
            .thumbInter,  
            .thumbTip,    
            .indexMeta,   
            .indexKnuc,   
            .indexBase,   
            .indexInter,  
            .indexTip,    
            .middleMeta,  
            .middleKnuc,  
            .middleBase,  
            .middleInter, 
            .middleTip,   
            .ringMeta,    
            .ringKnuc,    
            .ringBase,    
            .ringInter,   
            .ringTip,     
            .littleMeta,  
            .littleKnuc,  
            .littleBase,  
            .littleInter, 
            .littleTip,   
            .wrist,       
            .forearm,     
        ]

        touchThumb = [
            .indexTip,  
            .middleTip, 
            .ringTip,   
            .littleTip, 
        ]
    }

    public func parseHand(_ chiral: Chiral,
                          _ hand˚: Flo?) {
        guard let hand˚ else { return err( "hand˚ is nil") }

        self.chiral = chiral
        for (jointEnum, jointState) in self.joints {
            if jointState.parseJoint(chiral, hand˚, jointEnum) {
                /// parsed ok and `on == true`
                jointOn.insert(jointEnum)
            }
        }
        func err(_ msg: String) { PrintLog("⁉️ HandFlo::parseHand \(msg)") }
    }
    public func parseCanvas(_ touchCanvas: TouchCanvasDelegate,
                            _ chiral: Chiral,
                            _ root˚: Flo) {

        let parent˚ = root˚.bind("sky")
        if parent˚.name.hasPrefix("?") { return err("sky not found") }
        canvas.parseCanvas(touchCanvas, chiral, parent˚)
        func err(_ msg: String) { PrintLog("⁉️ HandFlo::parseCanvas \(msg)") }
    }

    public func trackAllJoints(on: Bool) {
        for jointEnum in jointOn {
            if let joint = joints[jointEnum] {
                joint.on = on
            }
        }
    }

    public func trackJoints(_ jointEnums: [JointEnum], on: Bool) {
        for jointEnum in jointEnums {
            if let jointItem = joints[jointEnum] {
                jointItem.on = on //_
            }
        }
    }

    public func updateThumbIndex() {
        var count = 0
        for jointEnum in touchThumb {
            if let jointState = joints[jointEnum] {
                count += jointState.updateThumbTip(thumbTip)
            }
        }
        if count > 0, let chiral {
            TimeLog(#function, interval: 4) { P(chiral.icon + "👍\(count)") }
        }

    }
    /// reserved for toggling palette on hand
    /// with index finger of other hand
    public func updateOtherHand(_ otherHand: HandPose) {

        var count = 0
        for jointEnum in otherHand.touchIndex {
            if let jointState = otherHand.joints[jointEnum] {
                count += jointState.updateOtherHandIndexTip(indexTip)
            }
        }
        if count > 0, let chiral {
            DebugLog { P( chiral.icon + "👆\(count)") }
        }
    }


}


