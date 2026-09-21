// created by musesum on 9/18/26

import AVFoundation
import CoreImage
import CoreVideo
import Metal
import QuartzCore
import UIKit
import MuFlo
import MuRouter // SubjectMask

/// one strip frame fed by a picked movie (Dreamatic AlbumSource.setVideo, loop mode):
/// a video-only composition, so the player has no audio track to render, and muted
/// besides — DeepMuse is the synthesizer, the clip never sounds. A rotated clip plays
/// through a video composition that applies its preferredTransform, so every decoded
/// frame (and the subject mask cut from it) is upright at the oriented size.
/// Player lifecycle runs on the main actor (AVPlayer is main-actor); `nextFrame`
/// is pulled by the render loop, and the live mask lands from the SubjectMask queue.
final class StripVideo: @unchecked Sendable {

    let url: URL
    private let lock = NSLock()
    private var output: AVPlayerItemVideoOutput?  // lock: set on main, pulled by the render loop
    private var liveMask: MTLTexture?             // lock: set by the SubjectMask queue
    private var wantsPlay = false                 // lock: pipe.strip on
    private var stopped = false                   // lock: torn down, drop a late setup

    // main actor
    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var loopObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    // render loop
    private var cache: CVMetalTextureCache?
    private var cvTex: CVMetalTexture?            // keeps the current frame's texture alive
    private(set) var pixelBuf: CVPixelBuffer?     // current frame, for the mask request
    private(set) var aspect: Float = 1            // oriented width / height
    var maskStale = false                         // a frame arrived since the last mask request
    /// this clip's own live mask: person segmentation is a stateful request (it smooths
    /// against its previous masks), so clips never share one (Dreamatic: one per stream)
    let live: SubjectMask

    /// decoded frames larger than this are scaled down (8 slots of 4K would jetsam)
    private static let maxSide: CGFloat = 2048

    /// `ciContext`: the host's shared Core Image context
    init(_ url: URL, _ device: MTLDevice, _ ciContext: CIContext) {
        self.url = url
        live = SubjectMask(ciContext: ciContext)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }

    /// build the player; `play` follows pipe.strip on
    func start(_ play: Bool) {
        lock.withLock { wantsPlay = play }
        Task { @MainActor [self] in await setup() }
    }
    /// pause while the strip is off, resume when on
    func play(_ on: Bool) {
        lock.withLock { wantsPlay = on }
        Task { @MainActor [self] in applyPlay() }
    }
    /// a new pick replaces this one
    func stop() {
        lock.withLock { stopped = true }
        Task { @MainActor [self] in teardown() }
    }
    var mask: MTLTexture? {
        get { lock.withLock { liveMask } }
        set { lock.withLock { liveMask = newValue } }
    }

    @MainActor private func setup() async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let props = try? await track.load(.timeRange, .preferredTransform, .naturalSize, .nominalFrameRate)
        else { return err("no video track") }
        let (range, transform, natural, fps) = props
        guard !lock.withLock({ stopped }) else { return }

        // video only: the source's audio tracks never enter the composition
        let comp = AVMutableComposition()
        guard let compTrack = comp.addMutableTrack(withMediaType: .video,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? compTrack.insertTimeRange(range, of: track, at: .zero)) != nil
        else { return err("composition") }
        compTrack.preferredTransform = transform

        // oriented size: the natural rect through preferredTransform
        let bounds = CGRect(origin: .zero, size: natural).applying(transform)
        let size = CGSize(width: bounds.width.rounded(), height: bounds.height.rounded())
        guard size.width > 0, size.height > 0 else { return err("size \(size)") }

        let item = AVPlayerItem(asset: comp)
        if !transform.isIdentity {
            // decode upright: move the rotated frame back to the origin
            let vc = AVMutableVideoComposition()
            vc.renderSize = size
            vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps > 0 ? min(60, max(1, fps.rounded())) : 30))
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
            layer.setTransform(transform.concatenating(
                CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)), at: .zero)
            instruction.layerInstructions = [layer]
            vc.instructions = [instruction]
            item.videoComposition = vc
        }
        var attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let longest = max(size.width, size.height)
        if longest > Self.maxSide {
            let s = Self.maxSide / longest
            attributes[kCVPixelBufferWidthKey as String] = Int((size.width * s).rounded())
            attributes[kCVPixelBufferHeightKey as String] = Int((size.height * s).rounded())
        }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true              // never unmuted; no AVAudioSession here
        player.actionAtItemEnd = .none     // the end observer loops
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.loop() }
            }
        // the system pauses a video player in the background; resume on return
        let active = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPlay() }
            }
        guard !lock.withLock({ stopped }) else {
            NotificationCenter.default.removeObserver(observer)
            NotificationCenter.default.removeObserver(active)
            item.remove(output)
            player.replaceCurrentItem(with: nil)
            return
        }
        self.item = item
        self.player = player
        self.loopObserver = observer
        self.activeObserver = active
        lock.withLock { self.output = output }
        applyPlay()
        DebugLog { P("🎞️ strip video \(self.url.lastPathComponent) \(Int(size.width))·\(Int(size.height)) fps \(Int(fps)) rotated \(!transform.isIdentity)") }

        func err(_ msg: String) {
            PrintLog("⁉️ StripVideo \(url.lastPathComponent): \(msg)")
        }
    }
    /// Dreamatic's default loop: back to the start and play on
    @MainActor private func loop() {
        guard let player else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        if lock.withLock({ wantsPlay && !stopped }) { player.play() }
    }
    @MainActor private func applyPlay() {
        guard let player else { return }
        if lock.withLock({ wantsPlay && !stopped }) { player.play() } else { player.pause() }
    }
    /// Dreamatic's teardown order: pause, drop the observers, detach the output,
    /// clear the item, then release — no async player op outlives its item
    @MainActor private func teardown() {
        player?.pause()
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        loopObserver = nil
        activeObserver = nil
        let output = lock.withLock { () -> AVPlayerItemVideoOutput? in
            defer { self.output = nil }
            return self.output
        }
        if let output { item?.remove(output) }
        player?.replaceCurrentItem(with: nil)
        item = nil
        player = nil
    }

    /// the newest decoded frame as a bgra texture through the frame cache
    /// (CameraSession's zero-copy path); nil when nothing new arrived
    func nextFrame() -> MTLTexture? {
        guard let output = lock.withLock({ output }), let cache else { return nil }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buf = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return nil }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        var imageTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buf, nil, MuComputePixelFormat, w, h, 0, &imageTex)
        guard let imageTex, let tex = CVMetalTextureGetTexture(imageTex) else { return nil }
        cvTex = imageTex
        pixelBuf = buf
        aspect = Float(max(1, w)) / Float(max(1, h))
        maskStale = true
        CVMetalTextureCacheFlush(cache, 0)   // release the frames no one holds
        return tex
    }
}
