
import AVKit
import MuFlo

public class RecordNode: ComputeNode, @unchecked Sendable {
    
    var isRecording = false
    var recordStart = TimeInterval(0)
    var assetWriter: AVAssetWriter?
    var assetInput: AVAssetWriterInput?
    var assetBuffer: AVAssetWriterInputPixelBufferAdaptor?
    var documentURL: URL?

    override public func computeShader(_ : MTLComputeCommandEncoder) {
    }
}
