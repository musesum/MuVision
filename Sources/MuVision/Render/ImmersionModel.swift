import SwiftUI
import MuFlo

#if os(visionOS)

/// Maintains app-wide immersion state with three modes.
@Observable
open class ImmersionModel {

    public enum State: String, CaseIterable, Identifiable {
        case windowed, mixed, full
        public var id: String { rawValue }
    }

    public var state: State = .windowed
    public var style: ImmersionStyle = .mixed {
        didSet { Self.fullNow = style is FullImmersionStyle }
    }
    public var isImmersed = false
    /// the style as last set; the eye buffer's zoom floor reads it off the render thread
    nonisolated(unsafe) public private(set) static var fullNow = false

    public init() {}

    public func changed(_ result: OpenImmersiveSpaceAction.Result) {
        switch result {
        case .opened:   isImmersed = true
        default:        isImmersed = false; state = .windowed
        }
    }
}
#endif
