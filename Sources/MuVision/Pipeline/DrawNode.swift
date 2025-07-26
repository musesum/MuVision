
import Foundation
import Metal
import MetalKit
import MuFlo
import MuHands

public class DrawNode: ComputeNode {

    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var shift˚  : Flo?
    private var touchDraw: TouchDraw
    private var touchCanvas: TouchCanvas

    public init(_ pipeline : Pipeline,
                _ pipeNode˚ : Flo,
                _ touchCanvas : TouchCanvas) {

        self.touchDraw = pipeline.touchDraw
        self.touchCanvas = touchCanvas

        super.init(pipeline, pipeNode˚)

        inTex˚  = pipeNode˚.superBindPath("in")
        outTex˚ = pipeNode˚.superBind("out") { flo, _ in
            if let tex = flo.texture {
                self.touchDraw.drawTex = tex
            }
        }
        shift˚  = pipeNode˚.superBindPath("shift")
        shader  = Shader(pipeline, file: "pipe.draw", kernel: "drawKernel")
        makeResources()
    }
    
    override open func makeResources() {
        pipeline.updateTexture(self, outTex˚)
        super.makeResources()
    }

    override public func computeShader(_ computeEnc: MTLComputeCommandEncoder)  {

        if let inTex = inTex˚?.texture {

            let pixSize = MemoryLayout<UInt32>.size
            let rowSize = inTex.width * pixSize
            let texSize = inTex.width * inTex.height * pixSize
            let drawBuf = UnsafeMutablePointer<UInt32>.allocate(capacity: texSize)
            let region = MTLRegionMake3D(0, 0, 0, inTex.width, inTex.height, 1)
            inTex.getBytes(drawBuf, bytesPerRow: rowSize, from: region, mipmapLevel: 0)
            
            touchDraw.drawIntoBuffer(drawBuf, CGSize(width: CGFloat(inTex.width), height: CGFloat(inTex.height)))
            touchCanvas.flushTouchCanvas()

            inTex.replace(region: region, mipmapLevel: 0, withBytes: drawBuf, bytesPerRow: rowSize)
            free(drawBuf)
        }
        shift˚?.updateMtlBuffer()
        computeEnc.setTexture(inTex˚,  index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        computeEnc.setBuffer (shift˚,  index: 0)
        computeEnc.setBuffer(pipeline.aspectBuf, offset: 0, index: 1)

        super.computeShader(computeEnc)
        outTex˚?.activate([], from: outTex˚)
    }
    

}
