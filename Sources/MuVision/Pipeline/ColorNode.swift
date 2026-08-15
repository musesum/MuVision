//  created by musesum on 2/22/19.

import Foundation
import Metal
import MetalKit
import MuFlo

public class ColorNode: ComputeNode {

    private var color˚  : ColorFlo!
    private var inTex˚  : Flo?
    private var palTex˚ : Flo?
    private var outTex˚ : Flo?
    private var plane˚  : Flo?
    private var height˚ : Flo?
    private var pairMix˚: Flo?

    public init(_ pipeline  : Pipeline,
                _ pipeNode˚ : Flo,
                _ ripples   : Ripples) {

        super.init(pipeline, pipeNode˚)
        color˚    = ColorFlo(pipeNode˚.getRoot(), ripples)
        inTex˚    = pipeNode˚.superBindPath("in")
        palTex˚   = pipeNode˚.superBindPath("pal")
        outTex˚   = pipeNode˚.superBindPath("out")
        plane˚    = pipeNode˚.superBindPath("plane")
        height˚   = pipeNode˚.superBindPath("height")
        pairMix˚  = pipeNode˚.superBindPath("pairMix")
        shader    = Shader(pipeline, "pipe.color", kernel: "colorKernel")
    }

    public override func makeResources() {
        computeTexture(outTex˚)
        paletteTexture(palTex˚)
        super.makeResources()
    }
    
    override public func updateUniforms() {
        // draw into palette texture
        if let palTex = palTex˚?.texture,
           let palBytes = color˚.getPal(256) {

            let palSize = 256
            let pixSize = MemoryLayout<UInt32>.size
            let palRegion = MTLRegionMake3D(0, 0, 0, palSize, 1, 1)
            let bytesPerRow = palSize * pixSize
            palTex.replace(region: palRegion,
                           mipmapLevel: 0,
                           withBytes: palBytes,
                           bytesPerRow: bytesPerRow)
        }
        plane˚?.updateMtlBuffer()
        height˚?.updateMtlBuffer()
        pairMix˚?.updateMtlBuffer()
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {
        updateUniforms()
        encoder.setTexture(inTex˚,    index: 0)
        encoder.setTexture(palTex˚,   index: 1)
        encoder.setTexture(outTex˚,   index: 2)
        encoder.setBuffer (plane˚,    index: 0)
        encoder.setBuffer (height˚,   index: 1)
        if pairMix˚?.buffer != nil {
            encoder.setBuffer(pairMix˚, index: 2)
        } else {
            var pairOff = Float(0) // no leaf in the script: keep the plain path
            encoder.setBytes(&pairOff, length: MemoryLayout<Float>.size, index: 2)
        }
        super.computeShader(encoder)
        outTex˚?.reactivate()
        palTex˚?.reactivate()
    }
    public override func logShader( _ logging: inout String,
                                    _ inOut: String) {
        let inAdr = inTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr)⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }
}

public typealias DrawTextureFunc = ((_ bytes: UnsafeMutablePointer<UInt32>,
                                     _ size: CGSize)->(Bool))

public typealias GetTextureFunc = ((_ size: Int) -> (UnsafeMutablePointer<UInt32>))
