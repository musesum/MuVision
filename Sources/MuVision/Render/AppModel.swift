/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Shared app state and renderers.
*/

import SwiftUI

#if os(visionOS)
/// Maintains app-wide state.
@Observable
open class AppModel {
    // App state
    public var isFirstLaunch = true
    public var showImmersiveSpace = false
    public var immersiveSpaceIsShown = false
    public var immersionStyle: ImmersionStyle = .mixed

    // Limb visibility
    public var upperLimbVisibility: Visibility = .visible
    public init() {}
}
#endif
