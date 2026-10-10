
import AVFoundation
import Metal
import UIKit
import os // OSAllocatedUnfairLock
import MuFlo
import MuRouter // SubjectMask

#if !os(visionOS)

/// One capture session, isolated to its own serial queue. Every call into
/// AVCaptureSession (configure, start, stop, lens switch, zoom, rotation)
/// runs on that queue in arrival order, so a `beginConfiguration` block can
/// no longer straddle a `startRunning` from another thread. The entry points
/// are synchronous and callable from any thread: each one enqueues and
/// returns. Frames never enter the actor: AVFoundation hands them to
/// `FrameSink` on the same queue, and the render thread reads the latest
/// through `cameraTex`, `maskTex` and `hasNewTex`.
///
/// iOS 18: `assumeIsolated` from the queue's own blocks needs the Swift 6
/// runtime's executor check.
@available(iOS 18.0, *)
public actor CameraSession {

    private let queue = DispatchSerialQueue(label: "Camera")
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private let captureSession = AVCaptureSession()
    private var captureDevice: AVCaptureDevice?
    private var cameraPos: AVCaptureDevice.Position
    private var cameraState: CameraState = .waiting
    private var wantOn = false         // the last setCameraOn request
    private var accessPending = false  // the access prompt is up
    private var configured = false     // input and output are in the session
    private let sink: FrameSink
    private let frames: OSAllocatedUnfairLock<Frames>
    private let observers = Observers()

    public init(position: AVCaptureDevice.Position = .front) {

        let frames = OSAllocatedUnfairLock(uncheckedState: Frames())
        self.frames = frames
        self.sink = FrameSink(MTLCreateSystemDefaultDevice(), frames)
        self.cameraPos = position
        enqueue { $0.observe() }
    }

    // MARK: - entry points, any thread

    /// turn the camera on or off; the first `on` asks for camera access and
    /// starts once it is granted
    public nonisolated func setCameraOn(_ on: Bool) {
        DebugLog { P("📷 setCameraOn(\(on))") }
        enqueue { $0.setOn(on) }
        NextFrame.shared.addBetweenFrame {
            Reset.reset()
        }
    }
    /// front (true) or back camera
    public nonisolated func facing(_ front: Bool) {
        enqueue { $0.setFacing(front) }
    }
    /// zoom, clamped to the device's range and 8×
    public nonisolated func setZoomFactor(_ factor: CGFloat) {
        enqueue { $0.setZoom(factor) }
    }
    /// the latest camera frame
    public nonisolated var cameraTex: MTLTexture? {
        frames.withLockUnchecked { $0.camera }
    }
    /// person mask of the latest frame, r8: white = subject; nil until the first result
    public nonisolated var maskTex: MTLTexture? {
        frames.withLockUnchecked { $0.mask }
    }
    public nonisolated var hasNewTex: Bool {
        frames.withLock { $0.streaming && $0.camera != nil }
    }

    /// run `body` on the camera queue after everything already queued; the
    /// queue is the actor's executor, so the block runs isolated
    private nonisolated func enqueue(_ body: @escaping @Sendable (isolated CameraSession) -> Void) {
        queue.async { self.assumeIsolated { body($0) } }
    }

    // MARK: - control, on the camera queue

    private func setOn(_ on: Bool) {
        wantOn = on
        switch cameraState {
        case .waiting:         if on { requestAccess() }
        case .ready, .stopped: if on { startRunning() }
        case .streaming:       if !on { stopRunning() }
        }
    }
    /// ask once; `accessGranted` starts the camera if it is still wanted
    private func requestAccess() {
        guard !accessPending else { return }
        accessPending = true
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            accessGranted(granted)
        }
    }
    private func accessGranted(_ granted: Bool) {
        accessPending = false
        guard granted else { return PrintLog("⁉️ CameraSession: camera access not granted") }
        cameraState = .ready
        if wantOn { startRunning() }
    }
    /// configure on the first run, then run
    private func startRunning() {
        if !configured {
            configured = true
            captureSession.beginConfiguration()
            addCaptureInput()
            addCaptureOutput()
            updateOrientation()
            captureSession.commitConfiguration()
        }
        captureSession.startRunning()
        updateOrientation()
        setState(.streaming)
    }
    private func stopRunning() {
        captureSession.stopRunning()
        setState(.stopped)
    }
    private func setState(_ state: CameraState) {
        cameraState = state
        let streaming = state == .streaming
        frames.withLock { $0.streaming = streaming }
    }
    /// remember the side; swap the input when the session has one
    private func setFacing(_ front: Bool) {
        let pos: AVCaptureDevice.Position = front ? .front : .back
        if configured, pos != cameraPos {
            cameraPos = pos
            captureSession.beginConfiguration()
            inputDevice = nil // didSet takes the old input out
            addCaptureInput()
            updateOrientation()
            captureSession.commitConfiguration()
        }
        cameraPos = pos
        if !front {
            setZoom(1) // back camera starts at widest lens
        }
    }
    /// clamp and apply zoom; a virtual back-camera device switches physical
    /// lenses automatically at its switch-over factors
    private func setZoom(_ factor: CGFloat) {
        guard let captureDevice,
              (try? captureDevice.lockForConfiguration()) != nil else { return }
        let lo = captureDevice.minAvailableVideoZoomFactor
        let hi = min(captureDevice.maxAvailableVideoZoomFactor, 8.0)
        captureDevice.videoZoomFactor = max(lo, min(factor, hi))
        captureDevice.unlockForConfiguration()
    }
    /// the session's runtime errors and the device's rotation, hopped onto the queue
    private func observe() {
        let center = NotificationCenter.default
        observers.tokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: captureSession, queue: nil) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
                self?.enqueue { $0.runtimeError(error) }
            })
        observers.tokens.append(center.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: nil) { [weak self] _ in
                self?.enqueue { $0.updateOrientation() }
            })
    }

    // MARK: - session, on the camera queue

    /// current capture input device
    private var inputDevice: AVCaptureDeviceInput? {
        didSet {
            if let oldValue {
                let from = oldValue.device.position.rawValue
                let to = inputDevice?.device.position.rawValue ?? 0
                DebugLog { P("📷 inputDevice: \(from) => \(to)") }
                captureSession.removeInput(oldValue)
            }
            if let inputDevice {
                captureSession.addInput(inputDevice)
            }
        }
    }
    /// current capture output data stream
    private var output: AVCaptureVideoDataOutput? {
        didSet {
            if let oldValue {
                captureSession.removeOutput(oldValue)
            }
            if let output {
                captureSession.addOutput(output)
            }
        }
    }
    /// capture input for `cameraPos`. The back camera prefers a virtual
    /// multi-lens device so videoZoomFactor switches to the best physical lens
    /// (ultra-wide / wide / tele), minimizing digital zoom; front stays single-lens
    private func addCaptureInput() {

        captureSession.sessionPreset = .hd1920x1080

        let camera: AVCaptureDevice?
        if cameraPos == .back {
            camera = AVCaptureDevice.default(.builtInTripleCamera,    for: .video, position: .back)
            ??       AVCaptureDevice.default(.builtInDualWideCamera,  for: .video, position: .back)
            ??       AVCaptureDevice.default(.builtInDualCamera,      for: .video, position: .back)
            ??       AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPos)
        }
        guard let camera else { return err("AVCaptureDevice") }
        captureDevice = camera
        guard let captureInput = try? AVCaptureDeviceInput(device: camera) else { return err("AVCaptureDeviceInput") }
        guard captureSession.canAddInput(captureInput) else { return err("canAddInput") }
        inputDevice = captureInput

        func err(_ str: String) {
            PrintLog("⚠️ CameraSession::addCaptureInput \(str)")
        }
    }
    /// capture output: BGRA frames to the sink, on the camera queue
    private func addCaptureOutput() {
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(sink, queue: queue)
        if captureSession.canAddOutput(out) {
            output = out
        } else {
            PrintLog("⁉️ CameraSession::addCaptureOutput: add output failed")
        }
    }
    /// level the horizon on the video connection and mirror the front camera
    private func updateOrientation() {
        guard let connection = output?.connection(with: .video),
              let captureDevice else { return }
        let rotator = AVCaptureDevice.RotationCoordinator(device: captureDevice, previewLayer: nil)
        connection.videoRotationAngle = rotator.videoRotationAngleForHorizonLevelCapture
        connection.isVideoMirrored = (cameraPos == .front)
    }
    /// `AVCaptureSession.runtimeErrorNotification` for this session
    private func runtimeError(_ error: (any Error)?) {
        if cameraState == .streaming {
            PrintLog("⁉️ CameraSession runtime error: \(error?.localizedDescription ?? "unknown")")
        }
    }

    // MARK: - frames, off the actor

    /// what the render thread reads: the latest frame, its person mask, and
    /// whether the session is streaming. Metal textures are thread-safe
    /// objects that the SDK does not mark Sendable, so the lock's unchecked
    /// state is the one place that is asserted: the camera queue and the
    /// mask queue write, the render thread reads
    private struct Frames {
        var camera: MTLTexture?
        var mask: MTLTexture?
        var streaming = false
    }
    /// notification tokens, removed when the session goes away
    private final class Observers {
        var tokens: [any NSObjectProtocol] = []
        deinit {
            for token in tokens { NotificationCenter.default.removeObserver(token) }
        }
    }
    /// keep the last few cache textures alive: an MTLTexture from
    /// CVMetalTextureGetTexture is only valid while its CVMetalTexture lives,
    /// and a frame still in flight on the GPU may sample one after the next
    /// replaces it
    private static let cvKept = 3
    private static func keep(_ cv: CVMetalTexture, in ring: inout [CVMetalTexture]) {
        ring.append(cv)
        if ring.count > cvKept { ring.removeFirst(ring.count - cvKept) }
    }

    /// AVFoundation's sample-buffer delegate. AVFoundation calls it on the
    /// camera queue one frame at a time, so its texture cache and its ring are
    /// confined to that queue by that contract: a sample buffer can't be sent
    /// into the actor, so the frames stay out here. Each frame becomes the
    /// camera texture, and goes to SubjectMask for its person mask
    private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

        private let frames: OSAllocatedUnfairLock<Frames>
        private let textureCache: CVMetalTextureCache?
        private var cameraCVs: [CVMetalTexture] = []
        private let subjectMask = SubjectMask()
        private let masks: MaskSink

        init(_ device: (any MTLDevice)?, _ frames: OSAllocatedUnfairLock<Frames>) {
            var cache: CVMetalTextureCache?
            if let device,
               CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) != kCVReturnSuccess {
                PrintLog("⁉️ CameraSession::FrameSink: texture cache failed")
            }
            self.frames = frames
            self.textureCache = cache
            self.masks = MaskSink(device, frames)
            super.init()
        }
        func captureOutput(_: AVCaptureOutput,
                           didOutput sampleBuf: CMSampleBuffer,
                           from _: AVCaptureConnection) {

            if let tex = texture(sampleBuf) {
                frames.withLockUnchecked { $0.camera = tex }
            }
            if let imageBuf = sampleBuf.imageBuffer {
                subjectMask.person(imageBuf) { [masks] mask in
                    masks.store(mask)
                }
            }
        }
        /// the frame through the texture cache
        private func texture(_ sampleBuf: CMSampleBuffer) -> MTLTexture? {
            guard let textureCache else { return err("textureCache") }
            guard let imageBuf = sampleBuf.imageBuffer else { return err("imageBuf") }

            let width  = CVPixelBufferGetWidth(imageBuf)
            let height = CVPixelBufferGetHeight(imageBuf)
            var imageTex: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuf, nil, MuComputePixelFormat, width, height, 0, &imageTex)

            guard let imageTex else { return err("imageTex") }
            guard let texture = CVMetalTextureGetTexture(imageTex) else { return err("get texture") }
            keep(imageTex, in: &cameraCVs)
            return texture

            func err(_ str: String) -> MTLTexture? {
                PrintLog("⁉️ CameraSession::texture: \(str)")
                return nil
            }
        }
    }
    /// the person mask of each frame as an r8 texture. SubjectMask calls back
    /// on its own serial queue, so this sink lives there: its cache and its
    /// ring are touched from nowhere else
    private final class MaskSink {

        private let device: (any MTLDevice)?
        private let frames: OSAllocatedUnfairLock<Frames>
        private let cache: CVMetalTextureCache?
        private var ring: [CVMetalTexture] = []
        private var failLogged = false

        init(_ device: (any MTLDevice)?, _ frames: OSAllocatedUnfairLock<Frames>) {
            var cache: CVMetalTextureCache?
            if let device {
                CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            }
            self.device = device
            self.frames = frames
            self.cache = cache
        }
        /// nil = no result for this frame; the last mask stays up
        func store(_ mask: CVPixelBuffer?) {
            guard let mask, let tex = texture(mask) else { return }
            frames.withLockUnchecked { $0.mask = tex }
        }
        /// one-channel mask buffer → r8 texture through the cache;
        /// a buffer the cache refuses (not IOSurface backed) is copied instead
        private func texture(_ buf: CVPixelBuffer) -> MTLTexture? {
            guard let device, let cache else { return nil }
            let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
            var cvTex: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buf, nil, .r8Unorm, w, h, 0, &cvTex)
            if let cvTex, let tex = CVMetalTextureGetTexture(cvTex) {
                keep(cvTex, in: &ring)
                return tex
            }
            if !failLogged {
                failLogged = true
                PrintLog("⁉️ CameraSession::maskTexture: cache status \(status) \(w)x\(h), copying")
            }
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = .shaderRead
            guard let tex = device.makeTexture(descriptor: desc) else { return nil }
            CVPixelBufferLockBaseAddress(buf, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: base, bytesPerRow: CVPixelBufferGetBytesPerRow(buf))
            return tex
        }
    }
}
#else
public final class CameraSession: NSObject {
    var camTex: MTLTexture?  // optional texture
}
#endif
