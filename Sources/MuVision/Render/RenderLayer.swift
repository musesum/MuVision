//  Created by musesum on 8/4/23.

#if os(visionOS)
import MetalKit
import Spatial
import CompositorServices
import simd
import MuFlo // NextFrame

open class RenderLayer: @unchecked Sendable {

    public static var viewports: [MTLViewport]!
    private let commandQueue: MTLCommandQueue
    private let dispatch = DispatchSemaphore(value: 3)
    public let renderer: LayerRenderer
    public let library: MTLLibrary
    public var rotation: Float = 0

    var pipeline: Pipeline
    var sceneTime = CFTimeInterval(0)
    var lastRenderTime = CFTimeInterval(0)

    public init(_ renderer: LayerRenderer,
                _ pipeline: Pipeline) {

        self.renderer = renderer
        self.pipeline = pipeline

        let device = MTLCreateSystemDefaultDevice()!
        self.library = device.makeDefaultLibrary()!
        self.commandQueue = device.makeCommandQueue()!

        self.lastRenderTime = CACurrentMediaTime()
        startRenderLoop()
    }

    public func startRenderLoop() {
        Task {
            let renderThread = Thread { [weak self] in
                guard let self else { return }
                self.renderLoop()
            }
            renderThread.start()
            try? await WorldTracking.shared.start()
        }
    }

    /// VisionOS replacement of NextFrame.shared
    func renderLoop() {
        while true {
            switch renderer.state {
            case .paused:  renderer.waitUntilRunning()
            case .running: autoreleasepool {
                if let frame = renderer.queryNextFrame() {
                    renderFrame(frame)
                }
            }
            case .invalidated: break
            @unknown default:  PrintLog("⁉️ RenderLayer::renderLoop @unknown default")
            }
        }
    }
}

extension RenderLayer {

    public func renderFrame(_ frame: LayerRenderer.Frame) {
        frame.startUpdate()
        performCpuWork()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        guard let drawable = frame.queryDrawable() else { return }

        // start commmand
        guard let commandBuf = commandQueue.makeCommandBuffer() else { fatalError("RenderLayer::renderFrame commandBuf") }

        frame.startSubmission()
        WorldTracking.shared.updateAnchor(drawable)
        runLayer(drawable, commandBuf)
        frame.endSubmission()

        func performCpuWork() {
            // this should execute pending Flo animations
            // while ignoring the metal based renderFrame()
            _ = NextFrame.shared.nextFrame(force: true)
        }
    }
    public func runLayer(_ drawable: LayerRenderer.Drawable,
                         _ commandBuf: MTLCommandBuffer) {

        guard let pipeSource = pipeline.pipeSource else { return }
        var logging = ""
        if let computeEnc = commandBuf.makeComputeCommandEncoder() {
            pipeSource.runCompute(computeEnc, &logging)
            computeEnc.endEncoding()
        }
        let renderPass = makeRenderPass(drawable: drawable)
        if let renderEnc = commandBuf.makeRenderCommandEncoder(descriptor: renderPass) {

            setViewMappings(renderEnc)

            pipeSource.runRender(renderEnc, drawable, &logging)
            renderEnc.endEncoding()

            drawable.encodePresent(commandBuffer: commandBuf)
            commandBuf.commit()
            commandBuf.waitUntilCompleted()
        }
        logging += "nil"
        TimeLog(#function, interval: 4) { P(logging) }

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

            RenderLayer.viewports = drawable.views.map { $0.textureMap.viewport }
            renderEnc.setViewports(RenderLayer.viewports)
            if drawable.views.count > 1 {
                var viewMappings = (0 ..< drawable.views.count).map {
                    MTLVertexAmplificationViewMapping(
                        viewportArrayIndexOffset: UInt32($0),
                        renderTargetArrayIndexOffset: UInt32($0))
                }
                renderEnc.setVertexAmplificationCount(
                    RenderLayer.viewports.count,
                    viewMappings: &viewMappings)
            }
        }
    }
}
#endif
