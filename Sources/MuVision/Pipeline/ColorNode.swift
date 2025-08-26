//  created by musesum on 2/22/19.

import Foundation
import Metal
import MetalKit
import MuFlo

public class ColorNode: ComputeNode {

    private var color˚     : ColorFlo!
    private var inTex˚     : Flo?
    private var palTex˚    : Flo?
    private var outTex˚    : Flo?
    private var displace˚ : Flo?
    private var plane˚     : Flo?
    private var height˚    : Flo?

    public init(_ pipeline  : Pipeline,
                _ pipeNode˚ : Flo,
                _ ripples   : Ripples) {

        super.init(pipeline, pipeNode˚)
        color˚    = ColorFlo(pipeNode˚.getRoot(), ripples)
        inTex˚    = pipeNode˚.superBindPath("in")
        palTex˚   = pipeNode˚.superBindPath("pal")
        outTex˚   = pipeNode˚.superBindPath("out")
        displace˚ = pipeNode˚.superBindPath("displace")
        plane˚    = pipeNode˚.superBindPath("plane")
        height˚   = pipeNode˚.superBindPath("height")
        shader    = Shader(pipeline,
                           file: "pipe.color",
                           kernel: "colorKernel")
        makeResources()
    }

    public override func makeResources() {
        computeTexture(outTex˚)
        paletteTexture(palTex˚)
        displaceTexture(displace˚)
        super.makeResources()
    }
    

    override public func updateUniforms() {
        super.updateUniforms()
        // draw into palette texture
        if let palTex = palTex˚?.texture {

            let palSize = 256
            let pixSize = MemoryLayout<UInt32>.size
            let palRegion = MTLRegionMake3D(0, 0, 0, palSize, 1, 1)
            let bytesPerRow = palSize * pixSize
            let palBytes = color˚.getPal(palSize)
            palTex.replace(region: palRegion,
                           mipmapLevel: 0,
                           withBytes: palBytes,
                           bytesPerRow: bytesPerRow)
        }
        plane˚?.updateMtlBuffer()
        height˚?.updateMtlBuffer()
    }

    override public func computeShader(_ computeEnc: MTLComputeCommandEncoder)  {

        computeEnc.setTexture(inTex˚,    index: 0)
        computeEnc.setTexture(palTex˚,   index: 1)
        computeEnc.setTexture(outTex˚,   index: 2)
        computeEnc.setTexture(displace˚, index: 3)
        computeEnc.setBuffer (plane˚,    index: 0)
        computeEnc.setBuffer (height˚,   index: 1)
        super.computeShader(computeEnc)
        outTex˚?.reactivate()
        palTex˚?.reactivate()
        displace˚?.reactivate()
    }
}

public typealias DrawTextureFunc = ((_ bytes: UnsafeMutablePointer<UInt32>,
                                     _ size: CGSize)->(Bool))

public typealias GetTextureFunc = ((_ size: Int) -> (UnsafeMutablePointer<UInt32>))
