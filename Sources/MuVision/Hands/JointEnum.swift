// created by musesum on 1/20/24

import ARKit

public enum JointEnum: Int {
    case canvas      = 0
    case thumbKnuc   = 1
    case thumbBase   = 2
    case thumbInter  = 3
    case thumbTip    = 4
    
    case indexMeta   = 5
    case indexKnuc   = 6
    case indexBase   = 7
    case indexInter  = 8
    case indexTip    = 9
    
    case middleMeta  = 10
    case middleKnuc  = 11
    case middleBase  = 12
    case middleInter = 13
    case middleTip   = 14
    
    case ringMeta    = 15
    case ringKnuc    = 16
    case ringBase    = 17
    case ringInter   = 18
    case ringTip     = 19
    
    case littleMeta  = 20
    case littleKnuc  = 21
    case littleBase  = 22
    case littleInter = 23
    case littleTip   = 24
    
    case wrist       = 25
    case forearm     = 26
    
    
    var name: String {
        switch self {
        case .canvas      : "canvas"
        case .thumbKnuc   : "thumb.knuc"
        case .thumbBase   : "thumb.base"
        case .thumbInter  : "thumb.inter"
        case .thumbTip    : "thumb.tip"
            
        case .indexMeta   : "index.meta"
        case .indexKnuc   : "index.knuc"
        case .indexBase   : "index.base"
        case .indexInter  : "index.inter"
        case .indexTip    : "index.tip"
            
        case .middleMeta  : "middle.meta"
        case .middleKnuc  : "middle.knuc"
        case .middleBase  : "middle.base"
        case .middleInter : "middle.inter"
        case .middleTip   : "middle.tip"
            
        case .ringMeta    : "ring.meta"
        case .ringKnuc    : "ring.knuc"
        case .ringBase    : "ring.base"
        case .ringInter   : "ring.inter"
        case .ringTip     : "ring.tip"
            
        case .littleMeta  : "little.meta"
        case .littleKnuc  : "little.knuc"
        case .littleBase  : "little.base"
        case .littleInter : "little.inter"
        case .littleTip   : "little.tip"
            
        case .wrist       : "wrist"
        case .forearm     : "forearm"
        }
    }
#if os(visionOS)
    var arJoint: HandSkeleton.JointName? {
        ARHandJoint[self]
    }
#endif
}
#if os(visionOS)
let ARHandJoint: [JointEnum: HandSkeleton.JointName] = [
    
    .thumbKnuc   : .thumbKnuckle,
    .thumbBase   : .thumbIntermediateBase,
    .thumbInter  : .thumbIntermediateTip,
    .thumbTip    : .thumbTip,
    .indexMeta   : .indexFingerMetacarpal,
    .indexKnuc   : .indexFingerKnuckle,
    .indexBase   : .indexFingerIntermediateBase,
    .indexInter  : .indexFingerIntermediateTip,
    .indexTip    : .indexFingerTip,
    .middleMeta  : .middleFingerMetacarpal,
    .middleKnuc  : .middleFingerKnuckle,
    .middleBase  : .middleFingerIntermediateBase,
    .middleInter : .middleFingerIntermediateTip,
    .middleTip   : .middleFingerTip,
    .ringMeta    : .ringFingerMetacarpal,
    .ringKnuc    : .ringFingerKnuckle,
    .ringBase    : .ringFingerIntermediateBase,
    .ringInter   : .ringFingerIntermediateTip,
    .ringTip     : .ringFingerTip,
    .littleMeta  : .littleFingerMetacarpal,
    .littleKnuc  : .littleFingerKnuckle,
    .littleBase  : .littleFingerIntermediateBase,
    .littleInter : .littleFingerIntermediateTip,
    .littleTip   : .littleFingerTip,
    .wrist       : .forearmWrist, // wrist?
    .forearm     : .forearmArm
]
#endif
