import Foundation
import Metal
import MetalKit
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

    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var shift˚  : Flo?
    private var touchDraw: TouchDraw
    private var touchCanvas: TouchCanvas
    private var dotsBuf: MTLBuffer?
    private var dotCountBuf: MTLBuffer
    private var drawTex: MTLTexture?

    public init(_ pipeline : Pipeline,
                _ flo˚ : Flo,
                _ touchCanvas : TouchCanvas) {

        self.touchDraw = pipeline.touchDraw
        self.touchCanvas = touchCanvas
        self.dotCountBuf = pipeline.device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        super.init(pipeline, flo˚)

        inTex˚  = flo˚.superBindPath("in")
        outTex˚ = flo˚.superBind("out") { flo, _ in
            if let tex = flo.texture {
                self.drawTex = tex
            }
        }
        shift˚ = flo˚.bind("shift")
        shader = Shader(pipeline, file: "pipe.draw", kernel: "drawDotKernel")
    }
    
    override open func makeResources() {
        computeTexture(outTex˚)
        super.makeResources()
    }

    public func updateInputBuffer() -> Bool {

        guard drawTex != nil  else { return false }
        guard let inTex˚ else { return false }
        if inTex˚.texture == nil {
            inTex˚.texture = drawTex
            self.drawTex = nil
            return true
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
    func updateDotsBuffer(_ computeEnc: MTLComputeCommandEncoder) {
        touchCanvas.flushTouchCanvas()

        // Build dots from touch input

        guard let inTex = inTex˚?.texture else { return }
        let texSize = CGSize(width: inTex.width, height: inTex.height)

        let drawPoints = touchCanvas.touchDraw.takeDrawPoints()
        var normPoints = [DrawPoint]()
        for drawPoint in drawPoints {
            let normPoint = drawPoint.normalize(touchCanvas.drawableSize, texSize)
            normPoints.append(normPoint)
        }

        // dotCount buffer (index 3)
        let count = UInt32(normPoints.count)
        dotCountBuf.contents().assumingMemoryBound(to: UInt32.self).pointee = count
        computeEnc.setBuffer(dotCountBuf, offset: 0, index: 3)

        // dots buffer (index 2)
        if normPoints.isEmpty {
            computeEnc.setBuffer(nil, offset: 0, index: 2)
        } else {
            let byteCount = normPoints.count * MemoryLayout<MetalDot>.stride
            if dotsBuf == nil || dotsBuf!.length < byteCount {
                dotsBuf = pipeline.device.makeBuffer(length: byteCount, options: .storageModeShared)
            }
            if let dotsBuf {
                normPoints.withUnsafeBytes { src in
                    if let base = src.baseAddress { memcpy(dotsBuf.contents(), base, min(src.count, dotsBuf.length)) }
                }
                computeEnc.setBuffer(dotsBuf, offset: 0, index: 2)
            }
        }
    }
    override public func computeShader(_ computeEnc: MTLComputeCommandEncoder)  {

        if updateInputBuffer() {
            _ = touchCanvas.touchDraw.takeDrawPoints()
        } else {
            updateDotsBuffer(computeEnc)
        }
        shift˚?.updateMtlBuffer()
        computeEnc.setTexture(inTex˚,  index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        computeEnc.setBuffer (shift˚,  index: 0)
        computeEnc.setBuffer(pipeline.aspectBuf, offset: 0, index: 1)

        super.computeShader(computeEnc)
        outTex˚?.reactivate()
    }
    

}
