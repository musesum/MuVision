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
    private var pipeRunning = false
    public var renderState: RenderState
    public var device = MTLCreateSystemDefaultDevice()!
    public var library: MTLLibrary!
    public var pipeSource: PipeNode?
    public var layer = CAMetalLayer()


//    internal var rotateClosure = [String: CallVoid]()
    internal var rotatable = [String: (MTLTexture,PipeNode,Flo)]()

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
    public var pipeSize = CGSize(width: 2048, height: 1024)

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
        pipeSize = CGSize(width: 2048, height: 2048) //....
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
        let clipFill = fillClip(in: pipeSize, out: layer.drawableSize)
        let clipNorm = clipFill.normalize()
        self.clipBuf = device.makeBuffer(clipNorm, "clipBuf")

        NoDebugLog { P("🧭 resizeFrame\(self.layer.drawableSize.digits()) clipNorm\(clipNorm.digits(2))") }

        for resizeNode in resizeNodes {
            resizeNode()
        }
    }
    public func renderFrame()  {

        if !pipeRunning { return }

        if renderState == .immersed { return }

        guard let pipeSource else { return }
        var logging = ""

        //performCpuWork()

        // start command
        guard let commandBuf = commandQueue.makeCommandBuffer() else { fatalError("Pipeline.renderFrame") }
        guard let drawable = layer.nextDrawable() else { return }

        // compute cycle
        if let ce = commandBuf.makeComputeCommandEncoder() {
            pipeSource.runCompute(ce, &logging)
            ce.endEncoding()
        }
        // render cycle
        let rp = renderPassDescriptor(drawable)
        if let re = commandBuf.makeRenderCommandEncoder(descriptor: rp) {
            pipeSource.runRender(re, &logging)
            re.endEncoding()
        }
        // finish
        commandBuf.present(drawable)
        commandBuf.commit()
        //commandBuf.waitUntilCompleted()

        logging += "nil"
        ///MuLog.TimeLog(#function, interval: 4) { P("🚰 "+logging) }
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
        #if false //..... immersive?
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].storeAction = .store
        rp.depthAttachment.loadAction = .clear
        rp.depthAttachment.storeAction = .store
        rp.depthAttachment.clearDepth = 1.0 //.... was 1
        #else
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        rp.depthAttachment.loadAction = .dontCare
        rp.depthAttachment.storeAction = .dontCare
        rp.depthAttachment.clearDepth = 1
        #endif
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


