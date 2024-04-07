//  Created by musesum on 8/4/23.

import MuFlo // NextFrame

let TripleBufferCount = 3

#if os(visionOS)
import MetalKit
import Spatial
import CompositorServices
import simd

open class RenderLayer {

    private let commandQueue: MTLCommandQueue
    private var touchCanvas: RenderLayerProtocol?
    private let inFlightSemaphore = DispatchSemaphore(value: TripleBufferCount)


    public let renderer: LayerRenderer
    public let device: MTLDevice
    public let library: MTLLibrary
    public var rotation: Float = 0
    public static var viewports: [MTLViewport]!
    public init(_ renderer: LayerRenderer) {

        self.renderer = renderer
        self.device = MTLCreateSystemDefaultDevice()!
        self.library = device.makeDefaultLibrary()!
        self.commandQueue = device.makeCommandQueue()!
    }

    public func setDelegate(_ touchCanvas: RenderLayerProtocol) {
        self.touchCanvas = touchCanvas
       touchCanvas.makeResources()
       touchCanvas.makePipeline()
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
        if renderer.configuration.layout == .layered {
            renderPass.renderTargetArrayLength = layerDrawable.views.count
        }
        return renderPass
    }

    func renderFrame() {

        guard let touchCanvas else { return }
        guard let frame = renderer.queryNextFrame() else { return }

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
        WorldTracking.shared.updateAnchor(drawable)
        
        touchCanvas.updateUniforms(drawable)

        // metal compute
        touchCanvas.computeLayer(commandBuf) //???

        // metal render
        touchCanvas.renderLayer(commandBuf, drawable)

        frame.endSubmission()
    }

    func performCpuWork() {
        // this should execute pending Flo animations
        // while ignoring the metal based renderFrame()
        _ = NextFrame.shared.nextFrames(force: true)
    }

    public func startRenderLoop() {
        Task {

            try? await WorldTracking.shared.start()


            let renderThread = Thread {
                self.renderLoop()
            }
            renderThread.name = "RenderThread"
            renderThread.start()
        }
    }

    func renderLoop() {
        while true {
            switch renderer.state {
            case .paused:  renderer.waitUntilRunning()
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
