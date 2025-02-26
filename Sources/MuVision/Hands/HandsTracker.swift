// created by musesum on 3/17/24

import ARKit
import MuFlo

#if os(visionOS)
open class HandsTracker: ObservableObject, @unchecked Sendable {

    let session = ARKitSession()
    var handTracking = HandTrackingProvider()
    let handsPose: LeftRight<HandPose>

    public init(_ handsFlo: LeftRight<HandPose>) {

        self.handsPose = handsFlo
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
                case .left : await handsPose.left.updateAnchor(update.anchor, handsPose.right)
                case .right: await handsPose.right.updateAnchor(update.anchor, handsPose.left)
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
