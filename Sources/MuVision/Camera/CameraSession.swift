
import AVFoundation
import Metal
import UIKit
import MuFlo

#if !os(visionOS)

public final class CameraSession: NSObject, @unchecked Sendable {

    private var isChangingFace = false
    private var isStartingNow = false
    private var captureDevice: AVCaptureDevice?
    private var captureSession = AVCaptureSession()
    private var cameraPos: AVCaptureDevice.Position = .front
    private var cameraState: CameraState = .waiting
    private var cameraQueue = DispatchQueue(label: "Camera", attributes: [])
    private var textureCache: CVMetalTextureCache?
    private var device = MTLCreateSystemDefaultDevice()
    private var videoOut: AVCaptureVideoDataOutputSampleBufferDelegate!

    public var cameraTex: MTLTexture?

    public init(_ videoOut: AVCaptureVideoDataOutputSampleBufferDelegate? = nil,
                position: AVCaptureDevice.Position = .front) {
        super.init()
        self.cameraPos = position
        self.videoOut = videoOut ?? self

        let errorName = NSNotification.Name.AVCaptureSessionRuntimeError
        let notification = NotificationCenter.default
        notification.addObserver(self, selector: #selector(captureError), name: errorName, object: nil)
        initOrientationObserver()
    }
    public var hasNewTex: Bool {
        cameraState == .streaming && cameraTex != nil
    }
    private func initCamera() {

        captureSession.beginConfiguration()
        initCaptureInput()
        initCaptureOutput()
        updateOrientation()
        captureSession.commitConfiguration()

        initTextureCache()
        captureSession.startRunning()
        cameraState = .streaming
    }

    private func cameraStart() {

        if isStartingNow { return }
        isStartingNow = true

        switch cameraState {

        case .waiting:

            requestCameraAccess()
            cameraQueue.async(execute: initCamera)

        case .ready, .stopped:

            cameraQueue.async {

                self.captureSession.startRunning()
                self.updateOrientation()
            }
            cameraState = .streaming

        case .streaming: break
        }
        isStartingNow = false
        NextFrame.shared.addBetweenFrame {
            Reset.reset()
        }
    }

    /// Stop the capture session.
    private func cameraStop() {

        cameraQueue.async {

            if  self.cameraState != .stopped {
                self.captureSession.stopRunning()
                self.cameraState = .stopped
            }
        }
        isStartingNow = false
    }

    public func setCameraOn(_ on: Bool) {

        if on {
            if cameraState != .streaming {
                cameraStart()
            }
        } else {
            if cameraState == .streaming {
                cameraStop()
            }
        }
        DebugLog { P("📷 setCameraOn(\(on))") }
        NextFrame.shared.addBetweenFrame {
            Reset.reset()
        }
    }

    public func facing(_ front: Bool) {
        if isChangingFace { return }
        isChangingFace = true
        cameraPos = front ? .front : .back
        captureSession.beginConfiguration()
        if let deviceInput = captureSession.inputs.first as? AVCaptureDeviceInput {
            captureSession.removeInput(deviceInput)
            initCaptureInput()
            updateOrientation()
        }
        captureSession.commitConfiguration()
        isChangingFace = false
        if !front {
            setZoomFactor(1) // back camera starts at widest lens
        }
    }

    /// Clamp and apply zoom on the camera queue; a virtual back-camera device
    /// switches physical lenses automatically at its switch-over factors.
    public func setZoomFactor(_ factor: CGFloat) {
        cameraQueue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }
            let lo = device.minAvailableVideoZoomFactor
            let hi = min(device.maxAvailableVideoZoomFactor, 8.0)
            device.videoZoomFactor = max(lo, min(factor, hi))
            device.unlockForConfiguration()
        }
    }

    /// Current capture input device.
    internal var inputDevice: AVCaptureDeviceInput? {
        didSet {
            if let oldValue {
                DebugLog { P("📷 inputDevice: \(oldValue.device.position.rawValue) => \(self.inputDevice?.device.position.rawValue ?? 0)") }
                captureSession.removeInput(oldValue)
            }
            if let inputDevice {
                captureSession.addInput(inputDevice)
            }
        }
    }

    /// Current capture output data stream.
    internal var output: AVCaptureVideoDataOutput? {
        didSet {
            if let oldValue {
                DebugLog { P("📷 output: \(oldValue) => \(self.output!)") }
                captureSession.removeOutput(oldValue)
            }
            if let output {
                captureSession.addOutput(output)
            }
        }
    }

    /// Requests access to camera hardware.
    fileprivate func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if !granted {
                PrintLog("⁉️ requestCameraAccess not granted")
            }  else if self.cameraState != .streaming {
                self.cameraState = .ready
            }
        }
    }

    /// camera frames to textures.
    private func initTextureCache() {

        guard let device,
              CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) == kCVReturnSuccess
        else {
            return PrintLog("⁉️ err \(#function): failed")
        }
    }

    //// initializes capture input device with media type and device position.
    fileprivate func initCaptureInput() {

        captureSession.sessionPreset = .hd1920x1080

        // back camera: prefer a virtual multi-lens device so videoZoomFactor
        // switches to the best physical lens (ultra-wide / wide / tele),
        // minimizing digital zoom; front stays single-lens
        let device: AVCaptureDevice?
        if cameraPos == .back {
            device = AVCaptureDevice.default(.builtInTripleCamera,    for: .video, position: .back)
            ??       AVCaptureDevice.default(.builtInDualWideCamera,  for: .video, position: .back)
            ??       AVCaptureDevice.default(.builtInDualCamera,      for: .video, position: .back)
            ??       AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        } else {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPos)
        }
        guard let captureDevice = device else { return err ("AVCaptureDevice") }
        self.captureDevice = captureDevice
        guard let captureInput = try? AVCaptureDeviceInput(device: captureDevice) else { return err ("AVCaptureDeviceInput") }
        guard captureSession.canAddInput(captureInput) else { return err ("canAddInput") }

        self.inputDevice = captureInput

        func err(_ str: String) {
            PrintLog("⚠️ CameraSession::initCaptureInput \(str)")
        }
    }

    // Helper function to set the appropriate AVCaptureVideoPreviewLayerOrientation based on device orientation
    func initOrientationObserver() {
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
            self.updateOrientation()
        }
    }

    func updateOrientation() {
        if let connection = output?.connection(with: .video),
           let captureDevice {

            let rotator = AVCaptureDevice.RotationCoordinator(device: captureDevice, previewLayer: nil)
            connection.videoRotationAngle =  rotator.videoRotationAngleForHorizonLevelCapture
            connection.isVideoMirrored = (self.cameraPos == .front)
        }
    }

    /// initialize capture output data stream.
    fileprivate func initCaptureOutput() {
        guard let videoOut else { return err("delegate == nil")}
        let out = AVCaptureVideoDataOutput()
        out.videoSettings =  [ kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA ]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(videoOut,
                                    queue: cameraQueue)
        if captureSession.canAddOutput(out) {
            self.output = out
        } else {
            err("add output failed")
        }
        func err(_ str: String) { PrintLog("⁉️ CameraSession::initCaptureOutput: \(str)") }
    }
    /// `AVCaptureSessionRuntimeErrorNotification` callback.
    @objc fileprivate func captureError() {

        if cameraState == .streaming {
            PrintLog("⁉️ CameraSession::captureSessionRuntimeError") }
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(_: AVCaptureOutput,
                              didOutput sampleBuf: CMSampleBuffer,
                              from _: AVCaptureConnection) {

        if let camTex = convert(sampleBuf) {
            self.cameraTex = camTex
        }
        func convert(_ sampleBuf: CMSampleBuffer) -> MTLTexture? {
            guard let textureCache else { return err("textureCache") }
            guard let imageBuf = sampleBuf.imageBuffer else { return err("imageBuf") }

            let width  = CVPixelBufferGetWidth(imageBuf)
            let height = CVPixelBufferGetHeight(imageBuf)
            var imageTex: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuf, nil, MuComputePixelFormat, width, height, 0, &imageTex)

            guard let imageTex else { return err("imageTex") }
            guard let texture = CVMetalTextureGetTexture(imageTex) else { return err("get texture")}
            return texture

            func err(_ str: String) -> MTLTexture? {
                PrintLog("⁉️ CameraSession::texture: \(str)")
                return nil
            }
        }
    }
}
#else
public final class CameraSession: NSObject {
    var camTex: MTLTexture?  // optional texture
}
#endif
