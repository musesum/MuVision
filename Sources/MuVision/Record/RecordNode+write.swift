//  created by musesum on 3/16/23.

import AVFoundation
import Photos
import MuFlo

@MainActor //_____
extension RecordNode {
    
    func removeURL(_ url: URL?) {
        guard let url = url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)

        }
    }
    func createOutputURL() -> URL? {
        documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        documentURL?.appendPathComponent("test.m4v")
        guard let docURL = documentURL else { PrintLog("⁉️ createOutputURL failed"); return nil  }
        removeURL(docURL)
        return docURL
    }


    func setupAssetWriter() -> AVAssetWriter? {
        func bail(_ msg: String) { PrintLog("⁉️ setupAssetWriter \(msg)") }
        guard let url = createOutputURL() else { return err("createOutputURL failed")}
        assetWriter = try? AVAssetWriter(outputURL: url, fileType: AVFileType.m4v)
        guard let assetWriter = assetWriter else { return err("⁉️ assetWriter: nil") }

        let outputSettings: [String: Any] =
        [ AVVideoCodecKey: AVVideoCodecType.h264,
          AVVideoWidthKey: pipeline.pipeSize.width,
         AVVideoHeightKey: pipeline.pipeSize.height ]

        assetInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
        guard let assetWriterInput = assetInput else { bail("assetWriterInput: nil"); return assetWriter }
        assetWriterInput.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pipeline.pipeSize.width,
            kCVPixelBufferHeightKey as String: pipeline.pipeSize.height ]

        assetBuffer = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes)

        assetWriter.add(assetWriterInput)
        return assetWriter
        func err(_ msg: String) -> AVAssetWriter?  {
            PrintLog("⁉️ setupAssetWriter \(msg)")
            return nil
        }
    }

    func startRecording(_ completion: @escaping ()->()) {
        if isRecording { return }

        if let assetWriter = setupAssetWriter() {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMTime.zero)

            recordStart = CACurrentMediaTime()
            isRecording = true
            completion()
        } else {
            completion()
        }
    }

    func endRecording(_ completion: @escaping ()->()) {

        if !isRecording { return }
        isRecording = false
        guard let assetInput else { return err("nil assetInput)") }
        guard let assetWriter else { return err("nil assetWriter)") }
        guard let documentURL else { return err("nil self.documentURL)") }

        assetInput.markAsFinished()
        assetWriter.finishWriting {

            switch PHPhotoLibrary.authorizationStatus() {

            case .notDetermined, .denied:
                
                PHPhotoLibrary.requestAuthorization { auth in
                    if auth == .authorized {
                        DispatchQueue.main.async {
                            self.saveInPhotoLibrary(documentURL)
                        }
                    }
                }
            case .authorized:

                DispatchQueue.main.async {
                    self.saveInPhotoLibrary(documentURL)
                }

            default: break
            }
        }
        completion()
        func err(_ msg: String) {
            PrintLog("⁉️ RecordNode::endRecording \(msg)"); completion()
        }
    }

    private func saveInPhotoLibrary(_ saveURL: URL) {

        PHPhotoLibrary.shared().performChanges({PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: saveURL)}) { completed, error in
            if completed {
                self.removeURL(self.documentURL)
                print("✔︎ \(#function) saved: \(saveURL.absoluteString)")
            } else if let error {  err("error: \(error)")
            } else { err("failed: \(saveURL.absoluteString)")
            }
        }
        func err(_ msg: String) {
            PrintLog("⁉️ RecordNode::saveInPhotoLibrary \(msg)")
        }
    }
    func writeFrame(_ texture: MTLTexture) {

        if !isRecording { return err("not recording") }
        guard let input = assetInput else { return err("assetWriterInput: nil)") }
        while !input.isReadyForMoreMediaData {} //!! TODO: can lockup UI

        guard let assetBuffer else { return err("nil assetBuffer") }
        guard let assetPool = assetBuffer.pixelBufferPool else { return err("nil assetPool")}

        // pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, assetPool, &pixelBuffer)
        if status != kCVReturnSuccess { return err("dropping frame...") }
        guard let pixelBuffer else { return err("nil pixelBuffer") }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else { return err("CVPixelBufferGetBaseAddress nil") }

        // stride may be rounded up to be 16-byte aligned
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(address, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        // get timeframe
        let frameTime = CACurrentMediaTime() - recordStart
        let presentationTime = CMTimeMakeWithSeconds(frameTime, preferredTimescale: 240)

        assetBuffer.append(pixelBuffer, withPresentationTime: presentationTime)

        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        func err(_ msg: String) {
            PrintLog("⁉️ RecordNode::writeFrame \(msg)")
        }
    }
}
