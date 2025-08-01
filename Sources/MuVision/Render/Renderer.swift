//  Created by musesum on 8/4/23.

#if os(visionOS)

import CompositorServices
import Metal
import MetalKit
import Spatial
import simd
import MuFlo // NextFrame

extension MemoryLayout {
    static var uniformStride: Int {
        // The 256 byte aligned size of the uniform structure.
        (size + 0xFF) & -0x100
    }
}
extension LayerRenderer.Clock.Instant.Duration {
    var timeInterval: TimeInterval {
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
    }
}

extension MTLDevice {
    var supportsMSAA: Bool {
        supportsTextureSampleCount(4) && supports32BitMSAA
    }
}


open class Renderer {

    var pipeline: Pipeline
    public var deviceAnchor: DeviceAnchor?

    // Metal
    private let device: MTLDevice
    private let supportsMSAA: Bool
    private let commandQueue: MTLCommandQueue
    nonisolated static let maxFramesInFlight: UInt64 = 3
    private let depthState: MTLDepthStencilState
    private var multisampleRenderTargets: [(color: MTLTexture, depth: MTLTexture)?]

    public let layerRenderer: LayerRenderer
    private var renderState: LayerRenderer.State = .invalidated
    public let nextFrame: NextFrame

    // ARKit
    private let arSession: ARKitSession
    private let worldTracking: WorldTrackingProvider

    public init(_ layerRenderer: LayerRenderer,
                _ pipeline: Pipeline,
                _ nextFrame: NextFrame)  {

        self.layerRenderer = layerRenderer
        self.pipeline = pipeline
        self.nextFrame = nextFrame

        self.device = layerRenderer.device
        supportsMSAA = layerRenderer.device.supportsMSAA
        self.commandQueue = self.device.makeCommandQueue()!
        multisampleRenderTargets = .init(repeating: nil, count: Int(Self.maxFramesInFlight))

        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = MTLCompareFunction.greater
        descriptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: descriptor)!

        arSession = ARKitSession()
        worldTracking = WorldTrackingProvider()
    }

    public func renderLoop(_ id: Int) async throws {

        // Setup ARKit Session
        let authorizations: [ARKitSession.AuthorizationType] = WorldTrackingProvider.requiredAuthorizations
        let dataProviders: [any DataProvider] = [worldTracking]

        _ = await arSession.requestAuthorization(for: authorizations)
        try await arSession.run(dataProviders)

        // Render loop
        while true {
            switch layerRenderer.state {
            case .invalidated:
                arSession.stop()
                renderState = .invalidated
                PrintLog("🔄 RenderLoop .invalidated return id: \(id)")
                return
            case .paused:
                layerRenderer.waitUntilRunning()
            default:
                try await renderFrame()
            }
            if renderState != layerRenderer.state {
                renderState = layerRenderer.state
                var msg = ""
                switch layerRenderer.state {
                case .invalidated : msg = ".invalidated"
                case .paused      : msg = ".paused"
                case .running     : msg = ".running"
                default: break
                }
                PrintLog("🔄 RenderLoop \(msg) id: \(id)")
            }
        }
    }
}
extension Renderer {

    public func updateAnchor(_ drawable:  LayerRenderer.Drawable) {
        guard worldTracking.state == .running else { return }
        let time = LayerRenderer.Clock.Instant.epoch.duration(to:  drawable.frameTiming.presentationTime).timeInterval

        deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        drawable.deviceAnchor = deviceAnchor

        NoTimeLog(#function, interval: 4) {
            if let anchorNow = self.deviceAnchor?.originFromAnchorTransform.digits(){
                print("⚓️ origin    " + anchorNow)
            }
        }
    }

    public func renderFrame() async throws {
        guard let frame = layerRenderer.queryNextFrame() else { return }

        frame.startUpdate()
        performCpuWork()
        frame.endUpdate()

        guard let drawable = frame.queryDrawable() else { return }

        // start commmand
        guard let commandBuf = commandQueue.makeCommandBuffer() else { fatalError("Renderer::renderFrame commandBuf") }

        frame.startSubmission()
        updateAnchor(drawable)
        runLayer(drawable, commandBuf)
        frame.endSubmission()

        func performCpuWork() {
            // this should execute pending Flo animations
            // while ignoring the metal based renderFrame()
            _ = nextFrame.nextFrame(force: true) //... crash here
        }
    }
    public func runLayer(_ drawable: LayerRenderer.Drawable,
                         _ commandBuf: MTLCommandBuffer) {

        guard let pipeSource = pipeline.pipeSource else { return }
        var logging = "💧 "
        if let computeEnc = commandBuf.makeComputeCommandEncoder() {
            pipeSource.runCompute(computeEnc, &logging)
            computeEnc.endEncoding()
        }
        let renderPass = makeRenderPass(drawable: drawable)
        if let renderEnc = commandBuf.makeRenderCommandEncoder(descriptor: renderPass) {

            setViewMappings(renderEnc)

            pipeSource.runRender(renderEnc, drawable, deviceAnchor, &logging)
            renderEnc.endEncoding()

            drawable.encodePresent(commandBuffer: commandBuf)
            commandBuf.commit()
            commandBuf.waitUntilCompleted()
        }
        logging += "nil"
        NoTimeLog(#function, interval: 4) { P(logging) }

        func makeRenderPass(drawable: LayerRenderer.Drawable) -> MTLRenderPassDescriptor { //???? duplicate?

            let renderPass = MTLRenderPassDescriptor()
            renderPass.colorAttachments[0].texture = drawable.colorTextures[0]
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].storeAction = .store
            renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

            renderPass.depthAttachment.texture = drawable.depthTextures[0]
            renderPass.depthAttachment.loadAction = .clear
            renderPass.depthAttachment.storeAction = .store
            renderPass.depthAttachment.clearDepth = 0.0

            renderPass.rasterizationRateMap = drawable.rasterizationRateMaps.first
            renderPass.renderTargetArrayLength = drawable.views.count
            return renderPass
        }

        func setViewMappings(_ renderEnc : MTLRenderCommandEncoder) {

            pipeline.viewports = drawable.views.map { $0.textureMap.viewport }
            renderEnc.setViewports(pipeline.viewports)
            if drawable.views.count > 1 {
                var viewMappings = (0 ..< drawable.views.count).map {
                    MTLVertexAmplificationViewMapping(
                        viewportArrayIndexOffset: UInt32($0),
                        renderTargetArrayIndexOffset: UInt32($0))
                }
                renderEnc.setVertexAmplificationCount(
                    pipeline.viewports.count,
                    viewMappings: &viewMappings)
            }
        }
    }
}
#endif
