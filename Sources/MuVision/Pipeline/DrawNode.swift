
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

    public init(_ pipeline : Pipeline,
                _ pipeNode˚ : Flo,
                _ touchCanvas : TouchCanvas) {

        self.touchDraw = pipeline.touchDraw
        self.touchCanvas = touchCanvas
        self.dotCountBuf = pipeline.device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        super.init(pipeline, pipeNode˚)

        inTex˚  = pipeNode˚.superBindPath("in")
        outTex˚ = pipeNode˚.superBind("out") { flo, _ in
            if let tex = flo.texture {
                self.touchDraw.drawTex = tex
            }
        }
        shift˚  = pipeNode˚.superBindPath("shift")
        shader  = Shader(pipeline, file: "pipe.draw", kernel: "drawDotKernel")
        makeResources()
    }
    
    override open func makeResources() {
        pipeline.updateTexture(self, outTex˚)
        super.makeResources()
    }

    func updateDotsBuffer(_ computeEnc: MTLComputeCommandEncoder) {
        touchCanvas.flushTouchCanvas() //.....
        // Build dots from touch input

        guard let inTex = inTex˚?.texture else { return }
        let texSize = CGSize(width: inTex.width, height: inTex.height)

        let drawPoints = touchCanvas.touchDraw.drawPoints
        var normPoints = [DrawPoint]()
        for drawPoint in drawPoints {
            let normPoint = drawPoint.normalize(touchDraw.drawableSize, texSize)
            normPoints.append(normPoint)
        }
        touchCanvas.touchDraw.drawPoints.removeAll()

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

        updateDotsBuffer(computeEnc)
        
        shift˚?.updateMtlBuffer()
        computeEnc.setTexture(inTex˚,  index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        computeEnc.setBuffer (shift˚,  index: 0)
        computeEnc.setBuffer(pipeline.aspectBuf, offset: 0, index: 1)

        super.computeShader(computeEnc)
        outTex˚?.activate([], from: outTex˚)
    }
    

}
