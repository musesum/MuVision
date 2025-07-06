/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Shared app state and renderers.
*/

import SwiftUI
import MuFlo

#if os(visionOS)

/// Maintains app-wide immersion state.
@Observable
open class ImmersionModel {
    public var isFirstLaunch = true
    public var goImmersive = false
    public var isImmersive = false
    public var immersionStyle: ImmersionStyle = .mixed
    public init() {}

    public func changed(_ action: OpenImmersiveSpaceAction.Result) {
        switch action {

        case .opened:        isImmersive = true

        case .userCancelled: break //showMenu = false

        case .error:         fallthrough

        @unknown default:    isImmersive = false
                             goImmersive = false
        }
    }
}
#endif
