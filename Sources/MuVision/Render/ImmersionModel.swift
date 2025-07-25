
import SwiftUI
import MuFlo

#if os(visionOS)

/// Maintains app-wide immersion state.
@Observable
open class ImmersionModel {
    public var goImmersive = false
    public var isImmersive = false
    public init() {}

    func toggleImmersion() {

    }
    public func changed(_ result: OpenImmersiveSpaceAction.Result) {
        switch result {

        case .opened:        isImmersive = true

        case .userCancelled: fallthrough

        case .error:         fallthrough

        @unknown default:    isImmersive = false
                             goImmersive = false
        }
    }
}
#endif
