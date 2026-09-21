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


extension LayerRenderer.Drawable {
    /// a capture target: video or streaming seen outside the device; false below visionOS 26
    public var isCapture: Bool {
        if #available(visionOS 26.0, *) { return target == .capture }
        return false
    }
}

open class Renderer {

    var pipeline: Pipeline
    public var deviceAnchor: DeviceAnchor?
    /// true while frames carry a capture drawable beside the built-in one; the
    /// compositor task writes it, app nodes read it to route a capture pass
    nonisolated(unsafe) public private(set) static var captureActive = false

    // Metal
    private let device: MTLDevice
    private let supportsMSAA: Bool
    private let commandQueue: MTLCommandQueue
    nonisolated static let maxFramesInFlight: UInt64 = 3
    private let depthState: MTLDepthStencilState
    private var multisampleRenderTargets: [(color: MTLTexture, depth: MTLTexture)?]

    public let layerRenderer: LayerRenderer
    private var renderState: LayerRenderer.State = .invalidated
    /// set when the loop leaves; no forced tick outlives the space
    private var loopEnded = false
    /// whether the previous frame already reported a missing device anchor
    private var anchorMissing = false

    // ARKit
    private let arSession: ARKitSession
    private let worldTracking: WorldTrackingProvider

    public init(_ layerRenderer: LayerRenderer,
                _ pipeline: Pipeline)  {

        self.layerRenderer = layerRenderer
        self.pipeline = pipeline

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

    public func renderLoop() async throws {

        // Setup ARKit Session
        let authorizations: [ARKitSession.AuthorizationType] = WorldTrackingProvider.requiredAuthorizations
        let dataProviders: [any DataProvider] = [worldTracking]

        _ = await arSession.requestAuthorization(for: authorizations)
        try await arSession.run(dataProviders)

        // Render loop
        while true {
            switch layerRenderer.state {
            case .invalidated:
                loopEnded = true
                arSession.stop()
                renderState = .invalidated
                PrintLog("🎞️ RenderLoop .invalidated")
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
                PrintLog("🎞️ RenderLoop \(msg)")
            }
        }
    }
}
extension Renderer {

    /// stamp this frame's device anchor; false when none is available to stamp
    @discardableResult
    public func updateAnchor(_ drawable:  LayerRenderer.Drawable) -> Bool {
        guard worldTracking.state == .running else {
            deviceAnchor = nil
            return false
        }
        let time = LayerRenderer.Clock.Instant.epoch.duration(to:  drawable.frameTiming.presentationTime).timeInterval

        deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        guard let deviceAnchor else { return false }
        drawable.deviceAnchor = deviceAnchor

        NoTimeLog(#function, interval: 4) {
            if let anchorNow = self.deviceAnchor?.originFromAnchorTransform.digits(){
                print("⚓️ origin    " + anchorNow)
            }
        }
        return true
    }

    public func renderFrame() async throws {
        guard let frame = layerRenderer.queryNextFrame() else { return }

        frame.startUpdate()
        performCpuWork()
        frame.endUpdate()

        let drawables = nextDrawables(frame)
        guard !drawables.isEmpty else { return }
        reportCapture(drawables.contains { $0.isCapture })

        frame.startSubmission()
        // every queried drawable presents before endSubmission, the built-in first
        for drawable in drawables {
            present(drawable)
        }
        frame.endSubmission()

        func performCpuWork() {
            // pending Flo animations; the windowed main loop owns the tick once
            // the space is gone, so a dying loop never forces one alongside it
            guard !loopEnded, layerRenderer.state == .running else { return }
            _ = NextFrame.shared.nextFrame(force: true)
        }
    }
    /// log the anchor gap once at each edge, never per frame
    private func reportAnchor(missing: Bool) {
        guard anchorMissing != missing else { return }
        anchorMissing = missing
        DebugLog { P(missing
                     ? "🎞️ Renderer no device anchor: dropping frames"
                     : "🎞️ Renderer device anchor resumed") }
    }
    /// one command buffer per drawable; an anchor-less drawable still presents
    private func present(_ drawable: LayerRenderer.Drawable) {
        let desc = MTLCommandBufferDescriptor() //..
        desc.errorOptions = .encoderExecutionStatus
        guard let commandBuf = commandQueue.makeCommandBuffer(descriptor: desc) else { fatalError("Renderer::renderFrame commandBuf") }

        var presented = false
        if updateAnchor(drawable) {
            reportAnchor(missing: false)
            presented = runLayer(drawable, commandBuf)
        } else {
            reportAnchor(missing: true)
        }
        if !presented {
            // a queried drawable must present before endSubmission; the
            // compositor drops an anchor-less present without harm
            drawable.encodePresent(commandBuffer: commandBuf)
            commandBuf.commit()
        }
    }
    /// log the capture edge once each way, never per frame
    private func reportCapture(_ active: Bool) {
        guard Self.captureActive != active else { return }
        Self.captureActive = active
        DebugLog { P(active
                     ? "🎞️ Renderer capture drawable joined the frame"
                     : "🎞️ Renderer capture drawable left the frame") }
    }
    /// this frame's drawables, the built-in display first; a Reality Composer Pro
    /// capture adds a second one, and an empty array is a cancelled frame
    private func nextDrawables(_ frame: LayerRenderer.Frame) -> [LayerRenderer.Drawable] {
        if #available(visionOS 26.0, *) {
            return frame.queryDrawables().sorted { !$0.isCapture && $1.isCapture }
        }
        return frame.queryDrawable().map { [$0] } ?? []
    }
    /// true once the drawable was presented; the caller balances a false
    @discardableResult
    public func runLayer(_ drawable: LayerRenderer.Drawable,
                         _ commandBuf: MTLCommandBuffer) -> Bool {

        guard let pipeSource = pipeline.pipeSource else { return false }

        if let computeEncoder = commandBuf.makeComputeCommandEncoder() {
            pipeSource.runCompute(computeEncoder)
            computeEncoder.endEncoding()
        }
        let renderPass = makeRenderPass(drawable: drawable)
        var presented = false
        if let encoder = commandBuf.makeRenderCommandEncoder(descriptor: renderPass) {

            setViewMappings(encoder)

            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            encoder.setFrontFacing(.clockwise)

            pipeSource.runRender(encoder, drawable, deviceAnchor)
            encoder.endEncoding()

            drawable.encodePresent(commandBuffer: commandBuf)
            commandBuf.commit()
            commandBuf.waitUntilCompleted()
            presented = true
        }
        NoTimeLog(#function, interval: 4) {
            NextFrame.shared.addBetweenFrame {
                var logging = ""
                pipeSource.logNode(&logging, "")
                logging += "nil"
                P("🚰 "+logging)
            }
        }
        return presented

        func makeRenderPass(drawable: LayerRenderer.Drawable) -> MTLRenderPassDescriptor { //???? duplicate?

            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = drawable.colorTextures[0]
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].storeAction = .store
            // Passthrough: clear to transparent for passthrough
            rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

            rp.depthAttachment.texture = drawable.depthTextures[0]
            rp.depthAttachment.loadAction = .clear
            rp.depthAttachment.storeAction = .store
            rp.depthAttachment.clearDepth = 0.0

            // gaze tracking areas: no MSAA in this pass, so a plain store reaches the compositor
            TrackingAreas.passAreas = false
            if #available(visionOS 26.0, *),
               TrackingAreas.format != nil,
               let areas = drawable.trackingAreasTextures.first {

                rp.colorAttachments[1].texture = areas
                rp.colorAttachments[1].loadAction = .clear
                rp.colorAttachments[1].storeAction = .store
                rp.colorAttachments[1].clearColor = MTLClearColorMake(0, 0, 0, 0)
                TrackingAreas.passAreas = true
            }
            rp.rasterizationRateMap = drawable.rasterizationRateMaps.first
            rp.renderTargetArrayLength = drawable.views.count
            return rp
        }

        func setViewMappings(_ encoder : MTLRenderCommandEncoder) {

            pipeline.viewports = drawable.views.map { $0.textureMap.viewport }
            encoder.setViewports(pipeline.viewports)
            if drawable.views.count > 1 {
                var viewMappings = (0 ..< drawable.views.count).map {
                    MTLVertexAmplificationViewMapping(
                        viewportArrayIndexOffset: UInt32($0),
                        renderTargetArrayIndexOffset: UInt32($0))
                }
                encoder.setVertexAmplificationCount(
                    pipeline.viewports.count,
                    viewMappings: &viewMappings)
            }
        }
    }
}
#endif
