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
    public var showImmersiveSpace = false
    public var immersiveSpaceIsShown = false
    public var immersionStyle: ImmersionStyle = .mixed
    public var showMenu: Bool = true
    public init() {}

    public func changed(_ action: OpenImmersiveSpaceAction.Result) {
        switch action {
        case .opened:
            immersiveSpaceIsShown = true
        case .userCancelled:
            // stay in immersive state to allow user to use
            // only hand pose to control parameters
            // otherwise fallthrough to @nknown default to stop
            DebugLog{ P("👐👆 setting howMenu to false") }
            showMenu = false
            break
        case .error:
            fallthrough
        @unknown default:
            immersiveSpaceIsShown = false
            showImmersiveSpace = false
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
