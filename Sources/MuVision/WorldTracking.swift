// created by musesum on 2/3/24
#if os(visionOS)
import ARKit
import CompositorServices
import MuExtensions

open class WorldTracking {
    public static var shared = WorldTracking()

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

    public func updateAnchor(_ layerDrawable:  LayerRenderer.Drawable) {
        guard worldTracking.state == .running else { return }
        let time = LayerRenderer.Clock.Instant.epoch.duration(to:  layerDrawable.frameTiming.presentationTime).timeInterval

        deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        layerDrawable.deviceAnchor = deviceAnchor

        MuLog.NoLog("👁️⚓️origin", interval: 1, terminator: "") {
            if let anchorNow = self.deviceAnchor?.originFromAnchorTransform.script,
               self.anchorPrev != anchorNow {
                
                self.anchorPrev = anchorNow
                print("    " + anchorNow)
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
