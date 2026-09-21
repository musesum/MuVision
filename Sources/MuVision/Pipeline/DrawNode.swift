import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders
import MuFlo
import MuHands // touch

fileprivate struct MetalDot {
    var point: SIMD2<Float>
    var radius: Float
    var color: Float
    init(_ point: SIMD2<Float>, _ radius: Float, _ color: Float) {
        self.point = point
        self.radius = radius
        self.color = color
    }
}
public class DrawNode: ComputeNode {

    private var inTex˚      : Flo?
    private var outTex˚     : Flo?
    private var shift˚      : Flo?          // pipe.draw.shift, index/false layer shift, drawDotKernel buffer 0
    private var shiftReal˚  : Flo?          // pipe.draw.shiftReal, real layer shift, drawRealKernel buffer 0
    private var touchDraw   : TouchDraw
    private var touchCanvas : TouchCanvas
    private var dotsBuf     : MTLBuffer?
    private var dotCount    : Int = 0
    private var dotCountBuf : MTLBuffer
    private var drawTex     : MTLTexture?
    /// drawable pixel → texture fraction shown there by the cubemap; nil
    /// falls back to the flat aspect-fill mapping
    public var cubeMap      : ((SIMD2<Float>) -> SIMD2<Float>?)?
    /// screen fraction (tile.out) → fraction of tile.in (draw.out), the same fold
    /// tileKernel gathers pixels with; without it a stroke drifts off the finger
    /// whenever canvas.repeat/mirror are non-zero
    public var tileMap      : ((SIMD2<Float>) -> SIMD2<Float>)?

    // real color layer: rgba strokes outside the automata, `canvas.brush.paint`
    // x hue, y sat, z val, w = 1 paints here instead of the index layer
    private var real˚       : Flo?
    private var paint˚      : Flo?
    private var alpha˚      : Flo?                 // `canvas.brush.alpha` real stroke opacity
    private var realBack    : MTLTexture?          // ping-pong partner of real˚.texture
    private var realShader  : Shader?
    private var realCompute : MTLComputePipelineState?
    private var realDotsBuf : MTLBuffer?
    private var realCount   : Int = 0
    private var realCountBuf: MTLBuffer
    private var coverTex    : MTLTexture?          // pixels the open stroke has coated
    private var coverBack   : MTLTexture?          // ping-pong partner of coverTex
    private var newStroke   = false                // first real dispatch of a stroke clears cover

    // per-brushstroke undo: the layer(s) the stroke touches plus the drawing
    // parameters, copied at each stroke group's first frame
    struct CanvasSnap {
        let index: MTLTexture?  // only when the stroke lands on the index layer
        let real: MTLTexture?   // only when it lands on the real layer
        let params: [(Flo, [(String, Double)])]
        let strings: [(Flo, String, [String])]
    }
    private var undoSnaps = [CanvasSnap]()  // pre-stroke states, oldest first
    private var redoSnaps = [CanvasSnap]()  // undone states, oldest first
    /// as many strokes as the budget holds; count fits the depth flo's range
    private let snapBudget = 256 << 20
    private let snapCount = 99
    private func snapBytes(_ s: CanvasSnap) -> Int {
        var bytes = 0
        if let t = s.index { bytes += t.width * t.height * 4 }
        if let t = s.real { bytes += t.width * t.height * 4 }
        return max(1, bytes)
    }
    private func trimSnaps() {
        var total = (undoSnaps + redoSnaps).reduce(0) { $0 + snapBytes($1) }
        while !undoSnaps.isEmpty, total > snapBudget || undoSnaps.count > snapCount {
            total -= snapBytes(undoSnaps.removeFirst())
        }
    }
    /// the settings a snapshot restores alongside the canvas, each set kept
    /// to the layer whose leaf writes it, so the real leaf's arrows never
    /// roll back what the false leaf is holding. canvas.alpha is on neither
    /// list: it is the cube face mix and the plato alpha, written by the
    /// hand, and replaying it on an undo blanked the cube
    private func params(_ paths: [String]) -> [(Flo, [String])] {
        guard let root = paint˚?.getRoot() else { return [] }
        return paths.compactMap { path -> (Flo, [String])? in
            guard let flo = root.findPath(path) else { return nil }
            return (flo, ["x", "y", "z", "w"].filter { flo.val($0) != nil })
        }
    }
    /// what the real leaf's own controls write: the stroke's colour and its
    /// layer flag, the left arc's stroke alpha, the real pad's screen shift
    /// and the real tilt its button arms
    static let realParamPaths = ["canvas.brush.paint", "canvas.brush.alpha",
                                 "canvas.shiftReal", "canvas.brush.tiltReal",
                                 "canvas.brush.sizeReal", "canvas.brush.pressReal"]
    /// and what the false leaf's do: the brush row, the azimuth pad's colour
    /// frame and shift, the canvas repeat, the palettes and the preset slots
    static let indexParamPaths = ["canvas.brush.index", "canvas.brush.size", "canvas.brush.press",
                                  "canvas.brush.tilt", "canvas.brush.paint",
                                  "canvas.color", "canvas.repeat", "canvas.shift", "canvas.pick",
                                  "sky.color.xfade", "sky.color.fade",
                                  "sky.color.ofs0", "sky.color.ofs1"]
    private lazy var realParamFlos: [(Flo, [String])] = params(Self.realParamPaths)
    private lazy var indexParamFlos: [(Flo, [String])] = params(Self.indexParamPaths)
    private lazy var stringFlos: [Flo] = {
        guard let root = paint˚?.getRoot() else { return [] }
        return ["sky.color.pal0", "sky.color.pal1", "canvas.pick"].compactMap { root.findPath($0) }
    }()
    private var strokeOpen = false
    private var idleFrames = 0
    private let idleClose = 8               // quiet frames that close a stroke group
    private var pendingUndo = 0
    private var pendingRedo = 0
    private let pendingLock = NSLock()      // pulses land on main; the ring runs on the render thread
    private var undo˚  : Flo?
    private var redo˚  : Flo?
    private var depth˚ : Flo?

    public init(_ pipeline : Pipeline,
                _ flo˚ : Flo,
                _ touchCanvas : TouchCanvas) {

        self.touchDraw = pipeline.touchDraw
        self.touchCanvas = touchCanvas
        self.dotCountBuf = pipeline.device.makeBuffer(
            length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        self.dotCountBuf.contents().assumingMemoryBound(to: UInt32.self).pointee = 0
        self.realCountBuf = pipeline.device.makeBuffer(
            length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        self.realCountBuf.contents().assumingMemoryBound(to: UInt32.self).pointee = 0
        super.init(pipeline, flo˚)

        inTex˚  = flo˚.superBindPath("in")
        outTex˚ = flo˚.superBind("out") { flo, _ in
            if let tex = flo.texture {
                self.drawTex = tex
            }
        }
        shift˚ = flo˚.bind("shift")
        shiftReal˚ = flo˚.bind("shiftReal")
        shader = Shader(pipeline, "pipe.draw", kernel: "drawDotKernel")
        real˚  = flo˚.findPath("real")
        paint˚ = flo˚.getRoot().findPath("canvas.brush.paint")
        alpha˚ = flo˚.getRoot().findPath("canvas.brush.alpha")
        if real˚ != nil {
            realShader = Shader(pipeline, "pipe.draw", kernel: "drawRealKernel")
        }
        let screen˚ = flo˚.getRoot().findPath("canvas.screen")
        depth˚ = screen˚?.findPath("depth")
        undo˚ = screen˚?.bind("undo") { [weak self] flo, visit in
            guard let self, flo.float > 0.5, visit.type.has([.user, .remote]) else { return }
            pendingLock.lock(); pendingUndo += 1; pendingLock.unlock()
        }
        redo˚ = screen˚?.bind("redo") { [weak self] flo, visit in
            guard let self, flo.float > 0.5, visit.type.has([.user, .remote]) else { return }
            pendingLock.lock(); pendingRedo += 1; pendingLock.unlock()
        }
        pipeline.resizeNodes.append { [weak self] in self?.resizedPipe() }
    }

    /// pipe.size remade the rotatable pair; the back buffers and the ring must match
    private func resizedPipe() {
        let side = Int(pipeline.pipeSize.width)
        if let realBack, realBack.width != side, let real˚ {
            self.realBack = makeComputeTex(size: pipeline.pipeSize, label: real˚.path(3) + ".back")
        }
        if let coverTex, coverTex.width != side {
            self.coverTex = makeComputeTex(size: pipeline.pipeSize, label: "draw.real.cover")
            self.coverBack = makeComputeTex(size: pipeline.pipeSize, label: "draw.real.cover.back")
        }
        let snapSide = undoSnaps.first.flatMap { $0.index?.width ?? $0.real?.width }
            ?? redoSnaps.first.flatMap { $0.index?.width ?? $0.real?.width } ?? side
        if snapSide != side {
            rescaleSnaps()
            strokeOpen = false
            updateDepth()
        }
    }
    /// a size change rescales the ring instead of dropping it: undo survives
    /// the parameter adjustment
    private func rescaleSnaps() {
        let size = pipeline.pipeSize
        let side = Int(size.width)
        let scaler = MPSImageBilinearScale(device: pipeline.device)
        func rescaled(_ snaps: [CanvasSnap], _ label: String) -> [CanvasSnap] {
            guard let commands = pipeline.commandQueue.makeCommandBuffer() else { return [] }
            var next = [CanvasSnap]()
            for snap in snaps {
                if (snap.index?.width ?? snap.real?.width ?? side) == side { next.append(snap); continue }
                var index: MTLTexture?
                var real: MTLTexture?
                if let src = snap.index, let dst = makeComputeTex(size: size, label: label + ".index") {
                    scaler.encode(commandBuffer: commands, sourceTexture: src, destinationTexture: dst)
                    index = dst
                }
                if let src = snap.real, let dst = makeComputeTex(size: size, label: label + ".real") {
                    scaler.encode(commandBuffer: commands, sourceTexture: src, destinationTexture: dst)
                    real = dst
                }
                next.append(CanvasSnap(index: index, real: real, params: snap.params, strings: snap.strings))
            }
            commands.commit()
            commands.waitUntilCompleted()
            return next
        }
        undoSnaps = rescaled(undoSnaps, "draw.snap.undo")
        redoSnaps = rescaled(redoSnaps, "draw.snap.redo")
    }

    /// copy the touched layer(s) and the drawing state into a fresh snapshot
    private func captureSnap(index: Bool, real: Bool) -> CanvasSnap? {
        var pairs = [(MTLTexture, MTLTexture)]()
        var snapIndex: MTLTexture?
        var snapReal: MTLTexture?
        if index, let live = inTex˚?.texture,
           let snap = makeComputeTex(size: pipeline.pipeSize, label: "draw.snap.index") {
            pairs.append((live, snap)); snapIndex = snap
        }
        if real, let live = real˚?.texture,
           let snap = makeComputeTex(size: pipeline.pipeSize, label: "draw.snap.real") {
            pairs.append((live, snap)); snapReal = snap
        }
        guard !pairs.isEmpty, blit(pairs) else { return nil }
        // only the settings of the layer(s) this snapshot covers; the
        // palettes and the preset slots ride with the index layer, whose
        // leaf edits them
        var flos = real ? realParamFlos : []
        if index { flos += indexParamFlos }
        let params = flos.map { flo, names in
            (flo, names.compactMap { n in flo.val(n).map { (n, $0) } })
        }
        let strings = index ? stringFlos.map { ($0, $0.string, $0.strings) } : []
        return CanvasSnap(index: snapIndex, real: snapReal, params: params, strings: strings)
    }
    /// copy a snapshot back INTO the live pair: the router aliases the objects
    private func restoreSnap(_ snap: CanvasSnap) {
        var pairs = [(MTLTexture, MTLTexture)]()
        if let index = snap.index, let live = inTex˚?.texture { pairs.append((index, live)) }
        if let real = snap.real, let live = real˚?.texture { pairs.append((real, live)) }
        _ = blit(pairs)
        for (flo, quote, quotes) in snap.strings {
            if !quotes.isEmpty { flo.setStrings(quotes, Visitor(0)) }
            else if !quote.isEmpty, quote != "??" { flo.setStringValue(quote, Visitor(0)) }
        }
        for (flo, vals) in snap.params where !vals.isEmpty {
            // the brush's w is the layer drawn on, owned by the paint leaf
            // shown: a snapshot from the other layer keeps its colour out
            // rather than flip the draw target under that leaf
            if flo === paint˚,
               let savedW = vals.first(where: { $0.0 == "w" })?.1,
               (savedW > 0.5) != paintReal { continue }
            flo.setNameNums(vals, .fire, Visitor(0))
        }
    }
    /// own command buffer: the frame's compute encoder is open on a different one
    private func blit(_ pairs: [(MTLTexture, MTLTexture)]) -> Bool {
        guard let commands = pipeline.commandQueue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return false }
        for (src, dst) in pairs where src.width == dst.width && src.height == dst.height {
            blit.copy(from: src, to: dst)
        }
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return true
    }
    /// the arrows count what they can actually step: the real layer's own
    /// snapshots, since both arrows live on the real leaf's bottom row
    private func updateDepth() {
        depth˚?.setNameNums([("x", Double(undoSnaps.count { $0.real != nil })),
                             ("y", Double(redoSnaps.count { $0.real != nil }))],
                            .fire, Visitor(0))
    }
    /// the newest snapshot that carries the real layer. A false stroke or a
    /// fill leaves an index-only snapshot, which the real leaf's arrows step
    /// over: they roll back the real layer's strokes and settings, nothing else
    static func popReal(_ snaps: inout [CanvasSnap]) -> CanvasSnap? {
        guard let i = snaps.lastIndex(where: { $0.real != nil }) else { return nil }
        return snaps.remove(at: i)
    }
    /// undo / redo pulses land between frames; applied before this frame's dots
    private func applyPendingHistory() {
        pendingLock.lock()
        let undos = pendingUndo; let redos = pendingRedo
        pendingUndo = 0; pendingRedo = 0
        pendingLock.unlock()
        if undos == 0, redos == 0 { return }
        for _ in 0 ..< undos {
            guard let snap = Self.popReal(&undoSnaps) else { break }
            // the redo capture mirrors the layers the undone stroke touched
            if let live = captureSnap(index: snap.index != nil, real: snap.real != nil) {
                redoSnaps.append(live)
            }
            restoreSnap(snap)
        }
        for _ in 0 ..< redos {
            guard let snap = Self.popReal(&redoSnaps) else { break }
            if let live = captureSnap(index: snap.index != nil, real: snap.real != nil) {
                undoSnaps.append(live)
            }
            restoreSnap(snap)
        }
        trimSnaps()
        strokeOpen = false
        idleFrames = 0
        updateDepth()
        DebugLog { P("🖌️ undo \(self.undoSnaps.count) redo \(self.redoSnaps.count)") }
    }
    /// a stroke group opens on the first frame with points; quiet frames close it
    private func trackStroke(_ normPoints: [DrawPoint]) {
        if normPoints.isEmpty {
            if strokeOpen {
                idleFrames += 1
                if idleFrames > idleClose { strokeOpen = false }
            }
        } else {
            if !strokeOpen {
                strokeOpen = true
                newStroke = true    // the real kernel starts a fresh coat
                // snapshot only the layer(s) this stroke lands on: a -1 fill or an
                // index stroke touches the index layer, a -2 clear or a real
                // stroke touches the real layer; never both from one command
                let real = paintReal && realCompute != nil
                let hasFill = normPoints.contains { $0.radius == -1 }
                let hasClear = normPoints.contains { $0.radius == -2 }
                let hasStroke = normPoints.contains { $0.radius >= 0 }
                if let snap = captureSnap(index: hasFill || (hasStroke && !real),
                                          real: hasClear || (hasStroke && real)) {
                    undoSnaps.append(snap)
                    redoSnaps.removeAll()
                    trimSnaps()
                    updateDepth()
                }
            }
            idleFrames = 0
        }
    }

    override open func makeResources() {
        computeTexture(outTex˚)
        super.makeResources()
        if let real˚ {
            computeTexture(real˚)
            realBack = makeComputeTex(size: pipeline.pipeSize, label: real˚.path(3) + ".back")
            coverTex = makeComputeTex(size: pipeline.pipeSize, label: "draw.real.cover")
            coverBack = makeComputeTex(size: pipeline.pipeSize, label: "draw.real.cover.back")
            if let fn = realShader?.kernelFunction {
                realCompute = try? pipeline.device.makeComputePipelineState(function: fn)
            }
        }
    }

    /// the paint layer: 1 real, 0 index
    private var paintReal: Bool { (paint˚?.val("w") ?? 0) > 0.5 }
    private var paintRgba: SIMD4<Float> {
        guard let paint˚ else { return SIMD4(1, 1, 1, 1) }
        let rgb = Hsv(Float(paint˚.val("x") ?? 0), Float(paint˚.val("y") ?? 1), Float(paint˚.val("z") ?? 1)).rgb()
        return SIMD4(rgb.r, rgb.g, rgb.b, Float(alpha˚?.val("x") ?? 1))
    }

    private func updateDrawPoints() {
        applyPendingHistory()
        if updateInputBuffer() {
            // an archive replaced the canvas: the ring is stale
            if !undoSnaps.isEmpty || !redoSnaps.isEmpty {
                undoSnaps.removeAll()
                redoSnaps.removeAll()
                strokeOpen = false
                updateDepth()
            }
        } else {
            let drawPoints = touchCanvas.touchDraw.takeDrawPoints()
            let normPoints = normalizePoints(drawPoints)
            touchCanvas.flushTouchCanvas()
            trackStroke(normPoints)
            updateDotsBuffer(normPoints)
        }

        func updateInputBuffer() -> Bool {

            guard drawTex != nil else { return false }
            guard let inTex˚ else { return false }
            if inTex˚.texture == nil {
                inTex˚.texture = drawTex
                self.drawTex = nil
            }
            guard let inTex = inTex˚.texture else { return false }
            guard let updateData = drawTex?.rawDataNoCopy() else { return false }

            let pixSize = MemoryLayout<UInt32>.size
            let rowSize = inTex.width * pixSize
            let texSize = inTex.width * inTex.height * pixSize
            let drawBuf = UnsafeMutablePointer<UInt32>.allocate(capacity: texSize)
            let region = MTLRegionMake3D(0, 0, 0, inTex.width, inTex.height, 1)
            let drawWidth  = max(inTex.width, inTex.height)
            let drawHeight = min(inTex.width, inTex.height)

            updateData.withUnsafeBytes {
                let ptr = $0.bindMemory(to: UInt32.self)
                for y in 0 ..< drawHeight {
                    for x in 0 ..< drawWidth {
                        let i = y * drawWidth + x
                        drawBuf[i] = ptr[i]
                    }
                }
            }
            inTex.replace(region: region, mipmapLevel: 0, withBytes: drawBuf, bytesPerRow: rowSize)
            free(drawBuf)
            self.drawTex = nil
            return true
        }
        func normalizePoints(_ drawPoints: [DrawPoint]) -> [DrawPoint] {
            let texSize: CGSize
            if let inTex = inTex˚?.texture {
                texSize = CGSize(width: inTex.width, height: inTex.height)
            } else if let outTex = outTex˚?.texture {
                texSize = CGSize(width: outTex.width, height: outTex.height)
            } else {
                texSize = pipeline.pipeSize
            }

            var normPoints = [DrawPoint]()
            for drawPoint in drawPoints {
                if drawPoint.radius >= 0, let cubeMap,
                   let uv = cubeMap(drawPoint.point) {
                    let mapped = tileMap?(uv) ?? uv
                    let p = SIMD2<Float>(mapped.x * Float(texSize.width), mapped.y * Float(texSize.height))
                    normPoints.append(DrawPoint(p, drawPoint.radius, drawPoint.color))
                } else if drawPoint.radius >= 0, let tileMap {
                    // flat path: normalize to draw-texture pixels, fold through the
                    // tile as a fraction, then scale back to pixels
                    let n = drawPoint.normalize(touchCanvas.drawableSize, texSize)
                    let f = SIMD2<Float>(n.point.x / Float(texSize.width), n.point.y / Float(texSize.height))
                    let mapped = tileMap(f)
                    let p = SIMD2<Float>(mapped.x * Float(texSize.width), mapped.y * Float(texSize.height))
                    normPoints.append(DrawPoint(p, drawPoint.radius, drawPoint.color))
                } else {
                    normPoints.append(drawPoint.normalize(touchCanvas.drawableSize, texSize))
                }
            }
            return normPoints
        }

        /// route by layer: a stroke (radius >= 0) goes to the index buffer or the
        /// real buffer depending on the paint layer, a -1 fill goes only to the
        /// index buffer and a -2 clear goes only to the real buffer; nothing
        /// ever lands in both
        func updateDotsBuffer(_ normPoints: [DrawPoint]) {
            let real = paintReal && realCompute != nil
            let indexPoints = normPoints.filter { $0.radius == -1 || ($0.radius >= 0 && !real) }
            let realPoints  = normPoints.filter { $0.radius == -2 || ($0.radius >= 0 && real) }
            dotCount = fill(&dotsBuf, dotCountBuf, indexPoints)
            realCount = fill(&realDotsBuf, realCountBuf, realPoints)
        }
        func fill(_ buf: inout MTLBuffer?, _ countBuf: MTLBuffer, _ points: [DrawPoint]) -> Int {
            countBuf.contents().assumingMemoryBound(to: UInt32.self).pointee = UInt32(points.count)
            let byteCount = max(1, points.count) * MemoryLayout<MetalDot>.stride
            if buf == nil || buf!.length != byteCount {
                buf = pipeline.device.makeBuffer(length: byteCount, options: .storageModeShared)
            }
            if let buf {
                points.withUnsafeBytes { src in
                    if let base = src.baseAddress {
                        memcpy(buf.contents(), base, byteCount)
                    }
                }
            }
            return points.count
        }
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {

        updateDrawPoints()
        shift˚?.updateMtlBuffer()

        let aspectBuf = pipeline.aspectBuf // aspect ratio

        // drawDotKernel: index/false layer, shifted by canvas.shift
        encoder.setTexture(inTex˚      , index: 0)
        encoder.setTexture(outTex˚     , index: 1)
        encoder.setBuffer (shift˚      , index: 0)
        encoder.setBuffer (aspectBuf   , offset: 0, index: 1)
        encoder.setBuffer (dotsBuf     , offset: 0, index: 2)
        encoder.setBuffer (dotCountBuf , offset: 0, index: 3)

        super.computeShader(encoder)
        outTex˚?.reactivate()
        computeReal(encoder)
    }

    /// real layer: shifted pass-through plus this frame's rgba dots, then swap
    /// the pairs; the cover pair rides along so one stroke lays one coat
    private func computeReal(_ encoder: MTLComputeCommandEncoder) {
        guard let real˚, let realCompute, let realBack,
              let coverTex, let coverBack,
              let realIn = real˚.texture else { return }
        shiftReal˚?.updateMtlBuffer()
        guard realCount > 0 || (shiftReal˚?.shiftWrapping ?? false) else { return }
        var rgba = paintRgba
        var fresh: UInt32 = newStroke ? 1 : 0
        encoder.setComputePipelineState(realCompute)
        encoder.setTexture(realIn,    index: 0)
        encoder.setTexture(realBack,  index: 1)
        encoder.setTexture(coverTex,  index: 2)
        encoder.setTexture(coverBack, index: 3)
        // drawRealKernel: real layer, shifted by canvas.shiftReal
        encoder.setBuffer (shiftReal˚,    index: 0)
        encoder.setBuffer (pipeline.aspectBuf, offset: 0, index: 1)
        encoder.setBuffer (realDotsBuf,  offset: 0, index: 2)
        encoder.setBuffer (realCountBuf, offset: 0, index: 3)
        encoder.setBytes  (&rgba, length: MemoryLayout<SIMD4<Float>>.size, index: 4)
        encoder.setBytes  (&fresh, length: MemoryLayout<UInt32>.size, index: 5)
        setupThreadGroup()
        encoder.dispatchThreadgroups(threadCount, threadsPerThreadgroup: threadSize)
        real˚.texture = realBack
        self.realBack = realIn
        self.coverTex = coverBack
        self.coverBack = coverTex
        newStroke = false
        real˚.reactivate()
    }


    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {

        let inAdr = inTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr)⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }
}
