//  created by musesum on 3/13/23.

import Collections
import MetalKit
import Metal
import MuFlo
import MuHands
#if os(visionOS)
import CompositorServices
#endif

open class Pipeline {

    internal var commandQueue: MTLCommandQueue!
    internal var drawBuf: MTLBuffer?
    internal var clipBuf: MTLBuffer?

    private var depthTex: MTLTexture!
    var pipeRunning = false // internal: Pipeline+size pauses the loop while textures are remade
    public var renderState: RenderState
    /// opt-in: the window layer keeps presenting while a space renders immersed;
    /// the immersed arm owns compute, the window arm draws its own pass
    public var dualPresent = false
    /// opt-in: the pass clears color and depth instead of .dontCare — a frame that
    /// draws nothing must present transparent pixels, not stale ones
    public var clearLoad = false
    /// the depth-clear value: 1 = far in normal Z; a reverse-Z host passes 0
    public var clearDepthFar: Double = 1
    public var device = MTLCreateSystemDefaultDevice()!
    public var library: MTLLibrary!
    public var pipeSource: PipeNode?
    public var layer = CAMetalLayer()

    internal var rotatable = [String:Flo]()

    /// the eyedropper's two flos: the request the menu and the canvas tap
    /// fill in, and the brush colour the frame answers with
    internal lazy var dropper˚: Flo? = root˚.findPath("canvas.dropper")
    internal lazy var paint˚: Flo? = root˚.findPath("canvas.brush.paint")

    private var aspect = Aspect.square
    private var _aspectBuf: MTLBuffer?
    public var aspectBuf: MTLBuffer? {
        if _aspectBuf == nil ||  aspect != pipeSize.aspect {
            aspect = pipeSize.aspect
            _aspectBuf = device.makeBuffer(aspect.rawValue)
            _aspectBuf?.label = "aspect"
        }
        return _aspectBuf
    }
    public var viewports = [MTLViewport]()

    public var resizeNodes = [CallVoid]()
    public var pipeSize = CGSize(width: 2048, height: 2048)

    internal var archive: ArchiveFlo
    public var root˚: Flo
    public var touchDraw: TouchDraw

    public init(_ root˚       : Flo,
                _ renderState : RenderState,
                _ archive     : ArchiveFlo,
                _ touchDraw   : TouchDraw,
                _ scale       : CGFloat,
                _ bounds      : CGRect) {

        self.root˚ = root˚
        self.renderState = renderState
        self.touchDraw = touchDraw
        self.archive = archive

        commandQueue = device.makeCommandQueue()
        library = device.makeDefaultLibrary()
        layer.device = device
        layer.pixelFormat = MuRenderPixelFormat
        layer.backgroundColor = nil
        layer.framebufferOnly = false
        layer.contentsGravity = .resizeAspectFill
        layer.bounds = layer.frame
        layer.contentsScale = scale
        pipeSize = CGSize(width: 2048, height: 2048)
#if os(visionOS)
        layer.frame = CGRect(x: 0, y: 0, width: pipeSize.width, height: pipeSize.height)
#else
        layer.frame = bounds
#endif
        PrintLog("layer.frame: \(layer.frame)")
        let pipe˚ = root˚.bind("pipe")
        pipeSource = PipeNode(self, pipe˚)
        pipeRunning = true
    }

    open func makePipeNode(_ childFlo: Flo,
                           _ pipeParent: PipeNode?) {
        let node: PipeNode
        switch childFlo.name {
        case "flat" : node = FlatNode(self, childFlo)
        case "cube" : node = CubeNode(self, childFlo)
        default     : node = PipeNode(self, childFlo)
        }
        pipeParent?.pipeChildren.append(node)
    }

    public func resizeFrame(_ frame    : CGRect,
                            _ drawSize : CGSize,
                            _ scale    : CGFloat,
                            _ onAppear : Bool) {

        // if user lays the device down on flat face
        // it is possible that orientation changes
        // without changing, if so then skip
        if !onAppear, frame == layer.frame { return }

        layer.frame = frame
        layer.drawableSize = drawSize
        layer.contentsScale = scale
        layer.layoutIfNeeded()

        // drawBuf
        self.drawBuf = device.makeBuffer(layer.drawableSize, "drawBuf")
        let trackFill = fillTrack(in: pipeSize, out: layer.drawableSize)
        let trackNorm = trackFill.normalize()
        self.clipBuf = device.makeBuffer(trackNorm, "clipBuf")

        DebugLog { P("🚰 resizeFrame\(self.layer.drawableSize.digits()) clipNorm\(trackNorm.digits(2))") }

        for resizeNode in resizeNodes {
            resizeNode()
        }
    }
    public func renderFrame()  {

        guard pipeRunning,
              renderState != .immersed || dualPresent,
              let pipeSource
        else { return }
        //performCpuWork()

        // start command
        let desc = MTLCommandBufferDescriptor() //.....
        desc.errorOptions = .encoderExecutionStatus
        guard let commandBuf = commandQueue.makeCommandBuffer(descriptor: desc) else { fatalError("Pipeline.renderFrame") }
        guard let drawable = layer.nextDrawable() else { return }
        // compute cycle — the immersed arm owns it while both arms present
        if renderState != .immersed,
           let commandEncoder = commandBuf.makeComputeCommandEncoder() {
            pipeSource.runCompute(commandEncoder)
            commandEncoder.endEncoding()
        }
        // render cycle
        let rp = renderPassDescriptor(drawable)
        if let renderEncoder = commandBuf.makeRenderCommandEncoder(descriptor: rp) {
            pipeSource.runRender(renderEncoder)
            renderEncoder.endEncoding()
        }
        // finish
        commandBuf.present(drawable)
        commandBuf.commit()
        commandBuf.waitUntilCompleted()

        // the frame is done and the drawable is still in scope: the only
        // moment the whole composite can be read a pixel at a time
        pickDropper(drawable.texture)

        if let error = commandBuf.error as NSError? {
            TimeLog("\(#function)", interval: 4) {

                P("🚰 commandBuf error: \(error)")
                if let encoderInfos =
                    error.userInfo[MTLCommandBufferEncoderInfoErrorKey]
                    as? [MTLCommandBufferEncoderInfo] {

                    for info in encoderInfos {
                        print(info.label + info.debugSignposts.joined())
                        if info.errorState == .faulted {
                            print(info.label + " faulted!")
                        }
                    }
                }
            }
        }
#if DEBUG
        // the chain prints between frames, so the throttle and its time prefix
        // belong with the print itself: a TimeLog out here fires before the
        // deferred body and strands a bare prefix on the console
        NextFrame.shared.addBetweenFrame {
            var logging = ""
            pipeSource.logNode(&logging, "")
            guard !logging.isEmpty else { return } // an empty chain logs nothing
            TimeLog("renderChain", interval: 4) { P("🚰 " + logging + "nil") }
        }
#endif
    }
}

extension Pipeline {

    public func renderPassDescriptor(_ drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {

        depthTex = updateDepthTex(
            Int(layer.drawableSize.width),
            Int(layer.drawableSize.height))
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = drawable.texture
        rp.depthAttachment.texture = depthTex
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        rp.colorAttachments[0].loadAction = clearLoad ? .clear : .dontCare
        rp.colorAttachments[0].storeAction = .store
        rp.depthAttachment.loadAction = clearLoad ? .clear : .dontCare
        rp.depthAttachment.storeAction = .dontCare
        rp.depthAttachment.clearDepth = clearDepthFar
        return rp
    }

    public func updateDepthTex(_ width: Int,
                               _ height: Int) -> MTLTexture? {

        if (depthTex == nil ||
            depthTex.width != width ||
            depthTex.height != height) {

            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float,
                width:  width,
                height: height,
                mipmapped: true)
            td.usage = .renderTarget
            td.storageMode = .memoryless
            return device.makeTexture(descriptor: td)
        } else {
            return depthTex
        }
    }
}


