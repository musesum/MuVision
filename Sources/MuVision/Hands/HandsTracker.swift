// created by musesum on 3/17/24

import ARKit
import MuFlo

#if os(visionOS)
open class HandsTracker: ObservableObject, @unchecked Sendable {

    let session = ARKitSession()
    var handTracking = HandTrackingProvider()
    let handsFlo: LeftRight<HandFlo>

    public init(_ handsFlo: LeftRight<HandFlo>) {

        self.handsFlo = handsFlo
    }
    public func startHands() async {

        do {
            if HandTrackingProvider.isSupported {
                print("ARKitSession starting.")
                try await session.run([handTracking])
            }
        } catch {
            print("ARKitSession error:", error)
        }
    }

    public func updateHands() async {

        for await update in handTracking.anchorUpdates {
            
            if update.event == .updated,
               update.anchor.isTracked {

                switch update.anchor.chirality {
                case .left : await handsFlo.left.updateAnchor(update.anchor, handsFlo.right)
                case .right: await handsFlo.right.updateAnchor(update.anchor, handsFlo.left)
                }
            }
        }
    }
    public func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(let type, let status):
                if type == .handTracking && status != .allowed {
                    // Achromsk the user to grant hand tracking authorization again in Settings.
                }
            default:
                print("Session event \(event)")
            }
        }
    }
}
#else
/// this is a stub for non-visionOS devices to
/// accept HandTracker events via MuPeer (Bonjour)
#endif
