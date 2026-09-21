// created by musesum on 9/9/26

import CoreImage
import Metal
import MetalKit
import UIKit
import UniformTypeIdentifiers
import MuFlo
import MuRouter // SubjectMask

/// one picked strip item: a still, or a movie file copied out of the picker
public enum StripItem: Sendable {
    case image(UIImage)
    case video(URL)
}

/// photo strip fed into the real layer: WinSky pic/Strip.cpp port with the
/// frames held as textures and the window cut by the strip kernel. The frames
/// sit side by side at their own aspect (each scaled to the strip's across span,
/// like `Strip::read` summing `totalXs`); the window slides along that strip and
/// wraps at its end (`getShift` modulo), so the feed is continuous on the torus.
/// A movie is one frame whose texture follows the playing clip (StripVideo), muted,
/// looping, paused while the strip is off. The picked set is saved under
/// Application Support and restored at launch.
public class StripNode: ComputeNode {

    /// app seam: present a photo picker and hand back the chosen stills and movies in order
    nonisolated(unsafe) public static var present: ((@escaping ([StripItem]) -> Void) -> Void)?

    private var outTex˚  : Flo?
    private var maskTex˚ : Flo?                  // subject masks, cut like the frames
    private var masks    = [MTLTexture]()        // r8 per frame, white = subject
    private let subject  = SubjectMask(ciContext: StripNode.ciContext) // stills, on load (video frames: StripVideo.live)
    /// guards the set (frames, masks, aspects, videos) and the motion state: load() swaps
    /// the set on main while the immersive render loop runs computeShader off main
    private let lock     = NSLock()
    private var axis˚    : Flo?
    private var slide˚   : Flo?
    private var mirror˚  : Flo?
    private var pick˚    : Flo?
    private var frames   = [MTLTexture]()
    private var aspects  = [Float]()             // width / height per frame
    private var count˚   : Flo?
    private var dirty    = true
    private var rate     = SIMD2<Float>(0, 0)   // frames per second along / across
    private var offset   = SIMD2<Float>(0, 0)   // along: across-span units; across: 0…1
    private var lastTime = CACurrentMediaTime()
    private var videos   = [StripVideo?]()       // per frame: nil = still
    private var playing  = false                 // pipe.strip on: videos play, else pause
    private var maskTime = 0.0                   // last live mask request
    private var maskNext = 0                     // round robin over the video frames
    private var maskBusy = false                 // a live mask request is running (one across all clips)
    /// live mask requests per second across all video frames (Vision person segmentation)
    private static let maskRate = 15.0
    /// one Core Image context for both mask paths (each context holds its own GPU heap)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    /// saved frames: Application Support/strip/<index>.jpg or .mov, in strip order
    private static var stripDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("strip", isDirectory: true)
    }

    public override init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        super.init(pipeline, pipeNode˚)
        outTex˚ = pipeNode˚.superBindPath("out")
        maskTex˚ = pipeNode˚.findPath("mask")
        axis˚   = pipeNode˚.superBindPath("axis")
        mirror˚ = pipeNode˚.superBindPath("mirror")
        count˚  = pipeNode˚.superBindPath("count")
        slide˚  = pipeNode˚.findPath("slide")
        pick˚   = pipeNode˚.findPath("pick")
        shader  = Shader(pipeline, "pipe.strip", kernel: "stripKernel")

        rate = slideRate(slide˚)
        axis˚?.addClosure   { [weak self] _,_ in self?.touch() }
        mirror˚?.addClosure { [weak self] _,_ in self?.touch() }
        slide˚?.addClosure  { [weak self] flo,_ in self?.touch(rate: self?.slideRate(flo) ?? .zero) }
        // the tap's user pulse only: an archive restore or a bind replays x 1 at launch,
        // and a LAN peer or tape replay carries .remote, none of which must present the
        // picker again (Dev 2026-09-09: pick once, keep the set; picked media is local
        // only, so a peer echo popping a modal on a device nobody touched is a bug, not
        // a sync feature)
        pick˚?.addClosure   { [weak self] flo, visit in
            guard let self, flo.float > 0.5, visit.type.has(.user) else { return }
            StripNode.present? { [weak self] items in
                // a cancelled picker keeps the current set (Dreamatic's nil pick)
                guard let self, !items.isEmpty else { return }
                if load(items, persist: true) > 0 { pipeFlo˚.setNameNums([("on", 1)], .fire, Visitor(0)) }
            }
        }
        // on only gates dispatch, so the videos pause with it (Dreamatic pauses an idle album);
        // registered before restore, whose on 1 starts the restored videos
        pipeNode˚.addClosure { [weak self] flo, _ in
            guard let self, let on = flo.val("on"), (on > 0) != playing else { return }
            playing = on > 0
            videos.forEach { $0?.play(playing) }
        }
        restore()
    }

    /// slide is an xy flo: `xyz` is nil without a z component, which zeroed the rate
    private func slideRate(_ flo: Flo?) -> SIMD2<Float> {
        guard let flo else { return .zero }
        let p = flo.cgPoint
        return SIMD2<Float>(Float(p.x), Float(p.y))
    }
    /// a flo change redraws the window; `rate` when the slide moved
    private func touch(rate newRate: SIMD2<Float>? = nil) {
        lock.withLock {
            if let newRate { rate = newRate }
            dirty = true
        }
    }

    /// stills → textures, movies → live frames; first eight, in picked order;
    /// `persist` writes them to disk; the previous set's players are torn down.
    /// The new set is built aside and swapped in under the lock; returns its frame count
    @discardableResult
    func load(_ picked: [StripItem], persist: Bool) -> Int {
        videos.forEach { $0?.stop() }
        let items = persist ? StripNode.save(Array(picked.prefix(8))) : Array(picked.prefix(8))
        playing = (pipeFlo˚.val("on") ?? 0) > 0
        let loader = MTKTextureLoader(device: pipeline.device)
        var textures = [MTLTexture]()
        var maskTextures = [MTLTexture]()
        var ratios = [Float]()
        var clips = [StripVideo?]()
        for item in items {
            switch item {
            case .image(let image):
                guard let cg = StripNode.upright(image),
                      let tex = try? loader.newTexture(cgImage: cg, options: [.SRGB: false]) else { continue }
                textures.append(tex)
                maskTextures.append(maskTexture(cg) ?? whiteMask)
                ratios.append(Float(max(1, tex.width)) / Float(max(1, tex.height)))
                clips.append(nil)
            case .video(let url):
                // black and whole-front until the first frame and mask; aspect follows the frames
                let video = StripVideo(url, pipeline.device, StripNode.ciContext)
                video.start(playing)
                textures.append(blankFrame)
                maskTextures.append(whiteMask)
                ratios.append(1)
                clips.append(video)
            }
        }
        // one swap: the render loop sees the old set or the new one, never a mix
        lock.withLock {
            frames = textures
            masks = maskTextures
            aspects = ratios
            videos = clips
            maskNext = 0
            offset = .zero
        }
        count˚?.setNameNums([("x", Double(textures.count))], .fire, Visitor(0))
        lock.withLock { dirty = true } // after count, so the redraw binds the new count
        DebugLog { P("🎞️ strip frames \(textures.count) videos \(clips.compactMap { $0 }.count)") }
        return textures.count
    }

    /// `UIImage.cgImage` drops imageOrientation: redraw a turned still upright (Dreamatic's orientedCG)
    private static func upright(_ image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.preferredRange = .standard   // 8-bit, like the decoded jpg
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(at: .zero) }.cgImage
    }

    /// each video frame swaps in its newest decoded texture and live mask;
    /// dirty only when one of them changed; under the lock (computeShader)
    private func pullVideos() {
        for (i, video) in videos.enumerated() {
            guard let video, i < frames.count else { continue }
            if let tex = video.nextFrame() {
                frames[i] = tex
                aspects[i] = video.aspect
                dirty = true
            }
            if let mask = video.mask, i < masks.count, mask !== masks[i] {
                masks[i] = mask
                dirty = true
            }
        }
        requestMask()
    }
    /// the camera's live path for a new video frame: person segmentation on the clip's
    /// own SubjectMask queue, without the luminance fallback (its polarity, re-picked each
    /// frame, swapped front and back on a busy clip); one request at a time across all
    /// clips, round robin, at most `maskRate` per second; under the lock (computeShader)
    private func requestMask() {
        let now = CACurrentMediaTime()
        guard !maskBusy, now - maskTime >= 1 / StripNode.maskRate, !videos.isEmpty else { return }
        let device = pipeline.device
        for k in 0 ..< videos.count {
            let i = (maskNext + k) % videos.count
            guard let video = videos[i], video.maskStale, let buf = video.pixelBuf else { continue }
            let taken = video.live.person(buf, luminanceFallback: false) { [weak self, weak video] mask in
                if let video, let mask { video.mask = StripNode.r8Texture(mask, device) }
                guard let self else { return }
                lock.withLock { maskBusy = false }
            }
            if taken {
                video.maskStale = false
                maskBusy = true
                maskTime = now
                maskNext = i + 1
            }
            return
        }
    }

    /// one r8 texture from the subject mask, registered onto the frame with the
    /// shared anti-alias treatment (Dreamatic's chain); nil when no subject is found
    private func maskTexture(_ cg: CGImage) -> MTLTexture? {
        guard let raw = subject.still(cg) else {
            DebugLog { P("🎭 strip mask none \(cg.width)·\(cg.height)") }
            return nil
        }
        let size = CGSize(width: cg.width, height: cg.height)
        let buf = subject.registeredBuffer(raw, onto: size) ?? raw
        guard let tex = StripNode.r8Texture(buf, pipeline.device) else { return nil }
        DebugLog { P("🎭 strip mask \(tex.width)·\(tex.height) coverage \(StripNode.coverage(buf).digits(2))") }
        return tex
    }
    /// one-channel mask buffer → its own r8 texture (a fresh one each time, so a
    /// live mask never overwrites a texture the GPU is sampling)
    private static func r8Texture(_ buf: CVPixelBuffer, _ device: MTLDevice) -> MTLTexture? {
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: td) else { return nil }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                    withBytes: base, bytesPerRow: CVPixelBufferGetBytesPerRow(buf))
        return tex
    }
    /// fraction of sampled mask pixels above half, for the mask instrument
    private static func coverage(_ buf: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return -1 }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let rowBytes = CVPixelBufferGetBytesPerRow(buf)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var lit = 0, total = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if p[y * rowBytes + x] > 127 { lit += 1 }
                total += 1
                x += 16
            }
            y += 16
        }
        return total > 0 ? Double(lit) / Double(total) : 0
    }
    /// no subject: the whole frame is the front
    private lazy var whiteMask: MTLTexture = {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
        let tex = pipeline.device.makeTexture(descriptor: td)!
        var white: UInt8 = 255
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 1)
        return tex
    }()
    /// a video frame before its first decoded picture
    private lazy var blankFrame: MTLTexture = {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MuComputePixelFormat, width: 1, height: 1, mipmapped: false)
        let tex = pipeline.device.makeTexture(descriptor: td)!
        var black: UInt32 = 0xFF000000
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        return tex
    }()

    /// a new pick replaces the old set: stills as NN.jpg, movies moved in as NN.<ext>,
    /// NN = picked position; hands back the items with each movie at its saved place
    private static func save(_ items: [StripItem]) -> [StripItem] {
        let fm = FileManager.default
        let dir = stripDir
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return items.enumerated().map { i, item in
            switch item {
            case .image(let image):
                if let data = image.jpegData(compressionQuality: 0.9) {
                    try? data.write(to: dir.appendingPathComponent(String(format: "%02d.jpg", i)), options: .atomic)
                }
                return item
            case .video(let url):
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
                let saved = dir.appendingPathComponent(String(format: "%02d.", i) + ext)
                do {
                    try fm.moveItem(at: url, to: saved)
                    return .video(saved)
                } catch {
                    PrintLog("⁉️ strip save \(url.lastPathComponent): \(error.localizedDescription)")
                    return item // plays from the picker copy this session only
                }
            }
        }
    }

    /// the saved set from the last pick, if any, in strip order
    private func restore() {
        let dir = StripNode.stripDir
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let items: [StripItem] = names.sorted().compactMap { name in
            let url = dir.appendingPathComponent(name)
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true { return .video(url) }
            return UIImage(contentsOfFile: url.path).map { .image($0) }
        }
        guard !items.isEmpty else { return }
        if load(items, persist: false) > 0 { pipeFlo˚.setNameNums([("on", 1)], .fire, Visitor(0)) }
        DebugLog { P("🎞️ strip restored \(items.count)") }
    }

    /// strip length in across-span units for the current axis: Σ aspect (horizontal) or Σ 1/aspect
    private var totalLength: Float {
        guard !aspects.isEmpty else { return 1 }
        let horizontal = (axis˚?.float ?? 0) < 0.5
        return aspects.reduce(0) { $0 + (horizontal ? $1 : 1 / max(0.01, $1)) }
    }

    public override func makeResources() {
        computeTexture(outTex˚)
        super.makeResources()
    }

    /// the strip moves at a constant rate: x in frames per second (mean frame length),
    /// y in across spans per second; both wrap, so the window rides the strip as a torus
    private func advance() {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - lastTime))
        lastTime = now
        guard rate != .zero, !frames.isEmpty else { return }
        let total = totalLength
        let mean = total / Float(frames.count)
        offset.x = (offset.x + rate.x * mean * dt).truncatingRemainder(dividingBy: total)
        offset.y = (offset.y + rate.y * dt).truncatingRemainder(dividingBy: 1)
        dirty = true
    }

    public override func computeShader(_ encoder: MTLComputeCommandEncoder) {
        // this tick's set, taken under the lock; the encoding below reads only these copies
        let tick: (frames: [MTLTexture], masks: [MTLTexture], aspects: [Float], offset: SIMD2<Float>)? = lock.withLock {
            advance()
            pullVideos()
            guard frames.count > 0, dirty else { return nil }
            dirty = false
            return (frames, masks, aspects, offset)
        }
        guard let tick else { return }
        let (frames, masks, aspects, offset) = tick
        axis˚?.updateMtlBuffer()
        mirror˚?.updateMtlBuffer()
        count˚?.updateMtlBuffer()
        encoder.setTexture(outTex˚, index: 1)
        var bound = frames
        while bound.count < 8 { bound.append(frames[0]) } // every slot bound; kernel clamps the index
        encoder.setTextures(bound, range: 2 ..< 10)
        encoder.setBuffer(axis˚,   index: 0)
        var ofs = offset
        encoder.setBytes(&ofs, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setBuffer(count˚,  index: 2)
        encoder.setBuffer(mirror˚, index: 3)
        var ratios = aspects
        while ratios.count < 8 { ratios.append(1) }
        encoder.setBytes(&ratios, length: MemoryLayout<Float>.size * 8, index: 4)
        super.computeShader(encoder)
        outTex˚?.activate()
        // the masks ride the same window
        if let maskTex˚, masks.count == frames.count {
            computeTexture(maskTex˚)
            encoder.setTexture(maskTex˚, index: 1)
            var boundMasks = masks
            while boundMasks.count < 8 { boundMasks.append(masks[0]) }
            encoder.setTextures(boundMasks, range: 2 ..< 10)
            super.computeShader(encoder)
            maskTex˚.activate()
        }
    }
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(lock.withLock { frames.count }) frames⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }
}
