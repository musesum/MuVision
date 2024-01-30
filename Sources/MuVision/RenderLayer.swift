//  Created by musesum on 8/4/23.

import MuFlo // NextFrame

let TripleBufferCount = 3

#if os(visionOS)

import MetalKit
import ARKit
import Spatial
import CompositorServices
import simd


open class RenderLayer {

    private let commandQueue: MTLCommandQueue
    private var delegate: RenderLayerProtocol?
    private let inFlightSemaphore = DispatchSemaphore(value: TripleBufferCount)
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    public let layerRenderer: LayerRenderer
    public let device: MTLDevice
    public let library: MTLLibrary
    public var rotation: Float = 0
    public static var viewports: [MTLViewport]!
    public init(_ layerRenderer: LayerRenderer) {

        self.layerRenderer = layerRenderer
        self.device = MTLCreateSystemDefaultDevice()!
        self.library = device.makeDefaultLibrary()!
        self.commandQueue = device.makeCommandQueue()!
    }

    public func setDelegate(_ delegate: RenderLayerProtocol) {
        self.delegate = delegate
       delegate.makeResources()
       delegate.makePipeline()
    }

    public func makeRenderPass(layerDrawable: LayerRenderer.Drawable) -> MTLRenderPassDescriptor {

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = layerDrawable.colorTextures[0]
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        renderPass.depthAttachment.texture = layerDrawable.depthTextures[0]
        renderPass.depthAttachment.loadAction = .clear
        renderPass.depthAttachment.storeAction = .store
        renderPass.depthAttachment.clearDepth = 0.0

        renderPass.rasterizationRateMap = layerDrawable.rasterizationRateMaps.first
        if layerRenderer.configuration.layout == .layered {
            renderPass.renderTargetArrayLength = layerDrawable.views.count
        }
        return renderPass
    }

    func renderFrame() {

        guard let delegate else { return }
        guard let frame = layerRenderer.queryNextFrame() else { return }

        frame.startUpdate()
        performCpuWork()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        guard let drawable = frame.queryDrawable() else { return }
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        guard let commandBuf = commandQueue.makeCommandBuffer() else { fatalError("renderFrame::commandBuf") }

        let semaphore = inFlightSemaphore
        commandBuf.addCompletedHandler { (_ commandBuf)-> Swift.Void in
            semaphore.signal()
        }

        frame.startSubmission()

        let time = LayerRenderer.Clock.Instant.epoch.duration(to:  drawable.frameTiming.presentationTime).timeInterval

        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        drawable.deviceAnchor = deviceAnchor

        delegate.updateUniforms(drawable)

        // metal compute
        delegate.computeLayer(commandBuf) //????

        // metal render
        delegate.renderLayer(commandBuf, drawable)

        frame.endSubmission()
    }

    func performCpuWork() {
        // this should execute pending Flo animations
        // while ignoring the metal based renderFrame()
        _ = NextFrame.shared.nextFrames(force: true)
    }

    public func startRenderLoop() {
        Task {
            do {
                try await arSession.run([worldTracking])
            } catch {
                fatalError("Failed to initialize ARSession")
            }

            let renderThread = Thread {
                self.renderLoop()
            }
            renderThread.name = "RenderThread"
            renderThread.start()
        }
    }

    func renderLoop() {
        while true {
            switch layerRenderer.state {
            case .paused:  layerRenderer.waitUntilRunning()
            case .running: autoreleasepool { renderFrame() }
            case .invalidated: break
            @unknown default:  print("⁉️ RenderLayer::runLoop @unknown default")
            }
        }
    }
    public static func setViewMappings(
        _ renderCmd     : MTLRenderCommandEncoder,
        _ layerDrawable : LayerRenderer.Drawable) {
            viewports = layerDrawable.views.map { $0.textureMap.viewport }
        renderCmd.setViewports(viewports)
        if layerDrawable.views.count > 1 {
            var viewMappings = (0 ..< layerDrawable.views.count).map {
                MTLVertexAmplificationViewMapping(
                    viewportArrayIndexOffset: UInt32($0),
                    renderTargetArrayIndexOffset: UInt32($0))
            }
            renderCmd.setVertexAmplificationCount(
                viewports.count,
                viewMappings: &viewMappings)

        }
    }
}
#endif
