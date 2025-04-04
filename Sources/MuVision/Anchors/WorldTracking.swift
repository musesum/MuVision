// created by musesum on 2/3/24
#if os(visionOS)
import ARKit
import CompositorServices
import MuFlo

open class WorldTracking {
    nonisolated(unsafe) public static var shared = WorldTracking()

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

    public func updateAnchor(_ drawable:  LayerRenderer.Drawable) {
        guard worldTracking.state == .running else { return }
        let time = LayerRenderer.Clock.Instant.epoch.duration(to:  drawable.frameTiming.presentationTime).timeInterval

        deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        drawable.deviceAnchor = deviceAnchor

        NoTimeLog(#function, interval: 1) {
            if let anchorNow = self.deviceAnchor?.originFromAnchorTransform.digits(),
               self.anchorPrev != anchorNow {
                
                self.anchorPrev = anchorNow
                print("👁️⚓️origin    " + anchorNow)
            }
        }
    }
    public func updateAnchorNow() {
        guard worldTracking.state == .running else { return }
        let now = Date().timeIntervalSince1970
        deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: now)
    }
}
#endif
