/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Shared app state and renderers.
*/

import SwiftUI
import MuFlo

public protocol ImmersionDelegate {
    func reshowMenu() async
}

#if os(visionOS)

/// Maintains app-wide immersion state.
@Observable
open class ImmersionModel: ImmersionDelegate {
    public var isFirstLaunch = true
    public var goImmersive = false
    public var isImmersive = false
    public var immersionStyle: ImmersionStyle = .mixed
    public var showMenu: Bool = true
    public init() {}

    public func changed(_ action: OpenImmersiveSpaceAction.Result) {
        switch action {

        case .opened:        isImmersive = true

        case .userCancelled: showMenu = false

        case .error:         fallthrough

        @unknown default:    isImmersive = false
                             goImmersive = false
        }
    }
    /// reshow menu -- not implemented
    public func reshowMenu() async {
        DebugLog{ P("👐 reshowMenu showMenu: \(self.showMenu) ") }
        if !showMenu {
            showMenu = true
            //... objectWillChange.send()
        }
    }
}
#endif
