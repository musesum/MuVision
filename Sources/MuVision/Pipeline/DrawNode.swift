
import Foundation
import Metal
import MetalKit
import MuFlo

public class DrawNode: ComputeNode {

    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var shift˚  : Flo?
    private var touchDraw: TouchDraw

    public override init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        self.touchDraw = pipeline.touchDraw
        super.init(pipeline, pipeNode˚)

        inTex˚  = pipeNode˚.superBindPath("in")
        outTex˚ = pipeNode˚.superBind("out") { flo, _ in
            if let tex = flo.texture {
                // Check if texture needs to be resized to match pipeline size
                if tex.width != Int(self.pipeline.pipeSize.width) || 
                   tex.height != Int(self.pipeline.pipeSize.height) {
                    // Create a new texture with the correct size and copy the content
                    if let resizedTex = self.resizeTextureWithAspectFill(tex) {
                        self.touchDraw.drawTex = resizedTex
                        flo.texture = resizedTex
                    } else {
                        self.touchDraw.drawTex = tex
                    }
                } else {
                    self.touchDraw.drawTex = tex
                }
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
            TouchCanvas.flushTouchCanvas()

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
    
    private func resizeTextureWithAspectFill(_ sourceTex: MTLTexture) -> MTLTexture? {
        let targetSize = pipeline.pipeSize
        
        // Create destination texture with pipeline size
        guard let destTex = pipeline.device.makeComputeTex(
            size: targetSize,
            label: sourceTex.label ?? "resized",
            format: sourceTex.pixelFormat) else { return nil }
        
        // Get source data
        guard let sourceData = sourceTex.rawData() else { return nil }
        
        let srcWidth = sourceTex.width
        let srcHeight = sourceTex.height
        let dstWidth = Int(targetSize.width)
        let dstHeight = Int(targetSize.height)
        
        // Calculate aspect fill scale
        let scaleX = CGFloat(dstWidth) / CGFloat(srcWidth)
        let scaleY = CGFloat(dstHeight) / CGFloat(srcHeight)
        let scale = max(scaleX, scaleY)
        
        // Calculate sample region
        let sampleWidth = CGFloat(dstWidth) / scale
        let sampleHeight = CGFloat(dstHeight) / scale
        let offsetX = (CGFloat(srcWidth) - sampleWidth) / 2.0
        let offsetY = (CGFloat(srcHeight) - sampleHeight) / 2.0
        
        // Create destination buffer
        let dstBytesPerRow = dstWidth * 4
        var dstData = [UInt8](repeating: 0, count: dstWidth * dstHeight * 4)
        
        sourceData.withUnsafeBytes { srcPtr in
            let src32Ptr = srcPtr.bindMemory(to: UInt32.self)
            dstData.withUnsafeMutableBytes { dstPtr in
                let dst32Ptr = dstPtr.bindMemory(to: UInt32.self)
                
                for dy in 0 ..< dstHeight {
                    for dx in 0 ..< dstWidth {
                        let srcX = CGFloat(dx) * sampleWidth / CGFloat(dstWidth) + offsetX
                        let srcY = CGFloat(dy) * sampleHeight / CGFloat(dstHeight) + offsetY
                        
                        let sx = Int(srcX)
                        let sy = Int(srcY)
                        
                        if sx >= 0 && sx < srcWidth && sy >= 0 && sy < srcHeight {
                            let srcIndex = sy * srcWidth + sx
                            let dstIndex = dy * dstWidth + dx
                            dst32Ptr[dstIndex] = src32Ptr[srcIndex]
                        }
                    }
                }
            }
        }
        
        // Copy to texture
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: dstWidth, height: dstHeight, depth: 1))
        destTex.replace(region: region, mipmapLevel: 0, withBytes: dstData, bytesPerRow: dstBytesPerRow)
        
        return destTex
    }
}
