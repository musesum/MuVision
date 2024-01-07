//  Created by musesum on 8/4/23.


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
    private let tripleSemaphore = DispatchSemaphore(value: TripleBufferCount)
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    public let layerRenderer: LayerRenderer
    public let device: MTLDevice
    public let library: MTLLibrary
    public var rotation: Float = 0

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
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

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
        guard let layerFrame = layerRenderer.queryNextFrame() else { return }

        layerFrame.startUpdate()
        // Perform frame independent work
        layerFrame.endUpdate()

        guard let timing = layerFrame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        guard let layerDrawable = layerFrame.queryDrawable() else { return }
        tripleSemaphore.wait()

        guard let commandBuf = commandQueue.makeCommandBuffer() else { fatalError("renderFrame::commandBuf") }
        
        commandBuf.addCompletedHandler { (_ commandBuf)-> Swift.Void in
            self.tripleSemaphore.signal()
        }

        layerFrame.startSubmission()
        let time = LayerRenderer.Clock.Instant.epoch.duration(to:  layerDrawable.frameTiming.presentationTime).timeInterval
        layerDrawable.deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        
        delegate.renderLayer(commandBuf, layerDrawable)
        
        layerFrame.endSubmission()
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
    public func setViewMappings(_ renderCmd     : MTLRenderCommandEncoder,
                                _ layerDrawable : LayerRenderer.Drawable,
                                _ viewports     : [MTLViewport]) {

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
