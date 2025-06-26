// created by musesum on 2/3/24
#if os(visionOS)
import ARKit
import CompositorServices
import MuFlo

open class WorldTracker {
    nonisolated(unsafe) public static var shared = WorldTracker()

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var running = false
    private var anchorPrev = ""
    public var deviceAnchor: DeviceAnchor?

    public init() {}

    func start() async throws {
        do {
            try await arSession.run([worldTracking])
            running = true
        } catch {
            fatalError("Failed to initialize ARSession")
        }
    }

    func stop() async throws {
        arSession.stop()
        running = false
    }

    public func updateAnchor(_ drawable:  LayerRenderer.Drawable) {
        guard worldTracking.state == .running else { return }
        let time = LayerRenderer.Clock.Instant.epoch.duration(to:  drawable.frameTiming.presentationTime).timeInterval

        deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        drawable.deviceAnchor = deviceAnchor

        TimeLog(#function, interval: 1) {
            if let anchorNow = self.deviceAnchor?.originFromAnchorTransform.digits(),
               self.anchorPrev != anchorNow {
                
                self.anchorPrev = anchorNow
                print("⚓️ origin    " + anchorNow)
            }
        }
    }
}
#endif
