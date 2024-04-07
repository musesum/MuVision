// created by musesum on 3/17/24

import Foundation

//  allow non-VisionOS to indicate Chirality handedness
public enum Chiral: Int {
    case either = 0
    case left   = 1
    case right  = 2
    var name: String {
        switch self {
        case .either : "either"
        case .left   : "left"
        case .right  : "right"
        }
    }
}
