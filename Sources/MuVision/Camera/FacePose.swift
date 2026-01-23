//  created by musesum on 2/18/23.

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import MuFlo
#if os(visionOS)
#else
public protocol FacePoseDelegate {
    func didUpdate(_ ciImage: CIImage)
}

open class FacePose: NSObject {

    private let pipeline: Pipeline
    private let facePose: FacePoseDelegate?
    private var faceMask: Bool

    private var visionSequence: VNSequenceRequestHandler!
    private var faceRectangles: VNDetectFaceRectanglesRequest!
    private var personSegment: VNGeneratePersonSegmentationRequest!
    private var angleColors: FaceAngleColors?
    private var ciContext: CIContext!
    private var camSession: CameraSession!

    var ciImage: CIImage? {
        didSet {
            if let ciImage {
                facePose?.didUpdate(ciImage)
            }
        }
    }

    public init(_ pipeline: Pipeline,
                _ faceMask: Bool,
                _ facePose: FacePoseDelegate? = nil) {

        self.pipeline = pipeline
        self.faceMask = faceMask
        self.facePose = facePose

        super.init()
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        ciContext = CIContext(mtlDevice: device)
        camSession = CameraSession(self, position: .front)
        camSession.setCameraOn(true)
        setupFacePose()
    }

    private func setupFacePose() {

        // The Vision requests and the handler to perform them.
        visionSequence = VNSequenceRequestHandler()
        personSegment = VNGeneratePersonSegmentationRequest()

        // Create a request to detect face rectangles.
        faceRectangles = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let face = request.results?.first as? VNFaceObservation else { return }
            // Generate RGB color intensity values for the face rectangle angles.
            self?.angleColors = FaceAngleColors(roll: face.roll, pitch: face.pitch, yaw: face.yaw)
        }
        faceRectangles.revision = VNDetectFaceRectanglesRequestRevision3

        // Create a request to segment a person from an image.
        personSegment = VNGeneratePersonSegmentationRequest()
        personSegment.qualityLevel = .balanced
        personSegment.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    private func processVideoFrame(_ pixelBuffer: CVPixelBuffer) {

        if  faceMask {
            // Perform the requests on the pixel buffer that contains the video frame.

            try? visionSequence.perform([faceRectangles, personSegment],
                                        on: pixelBuffer,
                                        orientation: .right)
            // Get the pixel buffer that contains the mask image.
            guard let maskBuffer =
                    personSegment.results?.first?.pixelBuffer else { return }

            ciImage = blend(original: pixelBuffer, mask: maskBuffer)
        } else {
            ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        }
    }

    private func blend(original framePixelBuffer: CVPixelBuffer,
                       mask maskPixelBuffer: CVPixelBuffer) -> CIImage? {

        guard let colors = angleColors else { return nil }

        // Create CIImage objects for the video frame and the segmentation mask.
        let originalImage = CIImage(cvPixelBuffer: framePixelBuffer).oriented(.right)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        // Scale the mask image to fit the bounds of the video frame.
        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        // Define RGB vectors for CIColorMatrix filter.
        let vectors = [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: colors.red),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: colors.green),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: colors.blue)
        ]

        // Create a colored background image.
        let backgroundImage = maskImage.applyingFilter("CIColorMatrix",
                                                       parameters: vectors)

        // Blend the original, background, and mask images.
        let blendFilter = CIFilter.blendWithRedMask()
        blendFilter.inputImage = originalImage
        blendFilter.backgroundImage = backgroundImage
        blendFilter.maskImage = maskImage

        // Set the new, blended image as current.
        return blendFilter.outputImage?.oriented(.left)
    }
}

// MARK: - Capture Video Data

extension FacePose: AVCaptureVideoDataOutputSampleBufferDelegate {
    @objc public func captureOutput(_ : AVCaptureOutput,
                                    didOutput sampleBuf: CMSampleBuffer,
                                    from _: AVCaptureConnection) {

        guard let imageBuf = sampleBuf.imageBuffer else { return }
        processVideoFrame(imageBuf)
    }
}

#endif
