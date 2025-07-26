//  MetPipeline.swift
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

    private var commandQueue: MTLCommandQueue!
    private var depthTex: MTLTexture!
    private var pipeRunning = false
    private var rotateFunc: MTLFunction?

    public  var renderState: RenderState

    public var device = MTLCreateSystemDefaultDevice()!
    public var library: MTLLibrary!
    public var pipeSource: PipeNode?
    public var layer = CAMetalLayer()
    public var drawBuf: MTLBuffer?
    public var clipBuf: MTLBuffer?

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
    public var pipeSize = CGSize._4K // size of draw surface
    public var rotateClosure = [String: CallVoid]()

    private var rotatable = [String: (MTLTexture,PipeNode,Flo)]()
    private var archive: ArchiveFlo!
    public var root˚: Flo
    public var touchDraw: TouchDraw

    public init(_ root˚: Flo,
                _ renderState: RenderState,
                _ archive: ArchiveFlo,
                _ touchDraw: TouchDraw,
                _ scale: CGFloat,
                _ bounds: CGRect) {

        self.root˚ = root˚
        self.renderState = renderState
        self.touchDraw = touchDraw
        self.archive = archive

        commandQueue = device.makeCommandQueue()
        library = device.makeDefaultLibrary()
        layer.device = device
        layer.pixelFormat = MetalRenderPixelFormat
        layer.backgroundColor = nil
        layer.framebufferOnly = false
        layer.contentsGravity = .resizeAspectFill
        layer.bounds = layer.frame
        layer.contentsScale = scale

        #if os(visionOS)
        layer.frame = CGRect(x: 0, y: 0, width: pipeSize.width, height: pipeSize.height)
        pipeSize = CGSize._4K
        #else
        
        self.layer.frame = bounds
        switch layer.frame.size.aspect {
        case .landscape : pipeSize = CGSize(width: 1920, height: 1080)
        default         : pipeSize = CGSize(width: 1080, height: 1920)
        }
        #endif

        let pipe˚ = root˚.bind("pipe")
        pipeSource = PipeNode(self, pipe˚)
        pipeRunning = true
    }

    open func makePipeNode(_ childFlo: Flo,
                           _ pipeParent: PipeNode?) {
        let pipeNode: PipeNode
        switch childFlo.name {
        case "flat" : pipeNode = FlatNode(self, childFlo)
        case "cube" : pipeNode = CubeNode(self, childFlo)
        default     : pipeNode = PipeNode(self, childFlo)
        }
        pipeParent?.pipeChildren.append(pipeNode)
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

        alignTextures()

        let clipFill = fillClip(in: pipeSize, out: layer.drawableSize)
        let clipNorm = clipFill.normalize()
        self.clipBuf = device.makeBuffer(clipNorm, "clipBuf")

        NoDebugLog { P("🧭 resizeFrame\(self.layer.drawableSize.digits()) clipNorm\(clipNorm.digits(2))") }

        for resizeNode in resizeNodes {
            resizeNode()
        }
    }
}

extension Pipeline {

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
        if let computeEnc = commandBuf.makeComputeCommandEncoder() {
            pipeSource.runCompute(computeEnc, &logging)
            computeEnc.endEncoding()
        }
        // render cycle
        if let renderEnc = commandBuf.makeRenderCommandEncoder(descriptor: renderPassDescriptor(drawable)) {
            pipeSource.runRender(renderEnc, &logging)
            renderEnc.endEncoding()
        }
        // finish command
        commandBuf.present(drawable)
        commandBuf.commit()
        commandBuf.waitUntilCompleted()

        logging += "nil"
        ///MuLog.TimeLog(#function, interval: 4) { P("🚰 "+logging) }
    }
    public func renderPassDescriptor(_ drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {

        updateDepthTex()

        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = drawable.texture
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        rp.depthAttachment.texture = self.depthTex
        rp.depthAttachment.loadAction = .dontCare
        rp.depthAttachment.storeAction = .dontCare
        rp.depthAttachment.clearDepth = 1
        return rp

        func updateDepthTex()  {

            let width  = Int(layer.drawableSize.width)
            let height = Int(layer.drawableSize.height)

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
                depthTex = device.makeTexture(descriptor: td)
            }
        }
    }
}

extension Pipeline {

    /// rotate textures to fit landscape/portrait aspect
    /// when user loads archive from other orientation
    public func alignNameTex() {

        for (name,tex) in archive.nameTex {
            guard let tex else { continue }

            if let newTex = rotateTexture(tex) {

                archive.nameTex[name] = newTex
                if let (_,node,flo) = rotatable[name] {
                    rotatable[name] = (newTex,node,flo)
                    flo.texture = aspectFill(newTex) ?? newTex
                    flo.activate([])
                }
            } else if let (_,node,flo) = rotatable[name] {
                rotatable[name] = (tex,node,flo)
                flo.texture = aspectFill(tex) ?? tex
                flo.activate([])
            } else {
                DebugLog { P("\(name) not found in rotatable") }
            }
        }
        activateRotateClosures()
    }

    public func activateRotateClosures() {
        for closure in rotateClosure.values {
            closure()
        }
    }

    /// adjust textures between landscape/portrait
    /// usually when user rotates iphone
    public func alignTextures() {

        guard layer.aspect != pipeSize.aspect else { return }
        pipeSize = pipeSize.withAspect(layer.aspect)

        for (name,(tex,node,flo)) in rotatable {
            if let newTex = rotateTexture(tex) {

                rotatable[name] = (newTex,node,flo)
                flo.texture = newTex
                flo.activate([])
            }
        }
        activateRotateClosures()
    }

    @inline(__always)
    func rotateTexture(_ inTex: MTLTexture) -> MTLTexture? {

        guard inTex.aspect != layer.aspect else { return nil }
        guard let outTex = makeRotateTex() else { return nil }

        if rotateFunc == nil {
            rotateFunc = library?.makeFunction(name: "rotateTexture")
        }
        guard let rotateFunc,
              let pipeState = try? device.makeComputePipelineState(function: rotateFunc)
        else {  PrintLog("Pipeline::\(#function) failed rotateFunc") ; return nil }

        // Set up a command buffer and encoder
        let commandBuf = commandQueue.makeCommandBuffer()!
        let computeEnc = commandBuf.makeComputeCommandEncoder()!
        computeEnc.setComputePipelineState(pipeState)

        // Bind in/out textures, with aspect buffer
        computeEnc.setTexture(inTex, index: 0)
        computeEnc.setTexture(outTex, index: 1)
        if let aspectBuf {
            computeEnc.setBuffer(aspectBuf, offset: 0, index: 0)
        }

        // Dispatch thread groups
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(width  : (inTex.width  + 15) / 16,
                                   height : (inTex.height + 15) / 16,
                                   depth  : 1)
        computeEnc.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)

        // End encoding and commit the command buffer
        computeEnc.endEncoding()
        commandBuf.commit()
        commandBuf.waitUntilCompleted()
        return outTex

        func makeRotateTex() -> MTLTexture? {
            let size = CGSize(width: inTex.height, height: inTex.width)
            if let tex = device.makeComputeTex(size: size,
                                               label: inTex.label,
                                               format: inTex.pixelFormat) {
                NoDebugLog { P("🧭 makeRotateTex for: \(tex.label ?? "??")") }
                return tex
            }
            return nil
        }
    }
    func aspectFill(_ sourceTex: MTLTexture) -> MTLTexture? {

        if CGFloat(sourceTex.width)   == pipeSize.width,
            CGFloat(sourceTex.height) == pipeSize.height {
            return sourceTex
        }

        // Create destination texture with pipeline size
        guard let destTex = device.makeComputeTex(
            size: pipeSize,
            label: sourceTex.label ?? "resized",
            format: sourceTex.pixelFormat) else { return nil }

        // Get source data
        guard let sourceData = sourceTex.rawData() else { return nil }

        let srcWidth = sourceTex.width
        let srcHeight = sourceTex.height
        let dstWidth = Int(pipeSize.width)
        let dstHeight = Int(pipeSize.height)

        // Calculate aspect fill scale
        let scaleX = CGFloat(dstWidth) / CGFloat(srcWidth)
        let scaleY = CGFloat(dstHeight) / CGFloat(srcHeight)
        let scale = max(scaleX, scaleY)

        // Calculate sample region
        let sampleWidth = CGFloat(dstWidth) / scale
        let sampleHeight = CGFloat(dstHeight) / scale
        let offsetX = (CGFloat(srcWidth) - sampleWidth) / 2.0
        let offsetY = (CGFloat(srcHeight) - sampleHeight) / 2.0

        // Create destination buffer
        let dstBytesPerRow = dstWidth * 4
        var dstData = [UInt8](repeating: 0, count: dstWidth * dstHeight * 4)

        sourceData.withUnsafeBytes { srcPtr in
            let src32Ptr = srcPtr.bindMemory(to: UInt32.self)
            dstData.withUnsafeMutableBytes { dstPtr in
                let dst32Ptr = dstPtr.bindMemory(to: UInt32.self)

                for dy in 0 ..< dstHeight {
                    for dx in 0 ..< dstWidth {
                        let srcX = CGFloat(dx) * sampleWidth / CGFloat(dstWidth) + offsetX
                        let srcY = CGFloat(dy) * sampleHeight / CGFloat(dstHeight) + offsetY

                        let sx = Int(srcX)
                        let sy = Int(srcY)

                        if sx >= 0 && sx < srcWidth && sy >= 0 && sy < srcHeight {
                            let srcIndex = sy * srcWidth + sx
                            let dstIndex = dy * dstWidth + dx
                            dst32Ptr[dstIndex] = src32Ptr[srcIndex]
                        }
                    }
                }
            }
        }

        // Copy to texture
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: dstWidth, height: dstHeight, depth: 1))
        destTex.replace(region: region, mipmapLevel: 0, withBytes: dstData, bytesPerRow: dstBytesPerRow)

        return destTex
    }

    public func customTexture(_ flo: Flo?,
                              _ makeTex: MakeTexture,
                              remake: Bool = false) {

        guard let flo else { return }

        if flo.texture == nil || remake,
           let tex = makeTex() {
            flo.texture = tex
            flo.activate([])
            NoDebugLog { P("🧭 \(#function) via: \(tex.label ?? "??")") }
        }
    }

    @discardableResult
    public func updateTexture(_ node: PipeNode,
                              _ flo: Flo?,
                              _ size: CGSize? = nil,
                              rotate: Bool = true) -> MTLTexture? {
        guard let flo else { return nil }

        let size = size ?? pipeSize
        if flo.texture?.aspect == size.aspect { return flo.texture }

        let path = flo.path(3)
        if let tex = device.makeComputeTex(size: size, label: path) {
            flo.texture = tex
            flo.activate([])

            if rotate {
                rotatable[path] = (tex, node, flo)
            }
            NoDebugLog { P("🧭 updateTexture\(size.digits(0)) \(path)") }
            return tex
        }
        return nil
    }


}
