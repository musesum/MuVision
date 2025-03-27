//  created by musesum on 2/22/19.

import Foundation
import Metal
import MetalKit
import MuFlo

public class ColorNode: ComputeNode {

    private var getPal  : GetTextureFunc?
    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var palTex˚ : Flo?
    private var plane˚  : Flo?

    override public init(_ pipeline : Pipeline,
                         _ childFlo : Flo) {

        super.init(pipeline, childFlo)
        
        getPal  = ColorFlo(pipeFlo.getRoot()).getMix
        inTex˚  = pipeFlo.superBindPath("in")
        outTex˚ = pipeFlo.superBindPath("out")
        palTex˚ = pipeFlo.superBindPath("pal")
        plane˚  = pipeFlo.superBindPath("plane")
        shader  = Shader(pipeline, file: "pipe.color", kernel: "colorKernel")
        makeResources()
    }

    public override func makeResources() {
        pipeline.updateTexture(self, outTex˚)
        let palSize = CGSize(width: 256, height: 1)
        pipeline.updateTexture(self, palTex˚, palSize, rotate: false)
        super.makeResources()
    }

    override public func updateUniforms() {
        super.updateUniforms()
        // draw into palette texture
        if let palTex = palTex˚?.texture,
           let getPal {

            let palSize = 256
            let pixSize = MemoryLayout<UInt32>.size
            let palRegion = MTLRegionMake3D(0, 0, 0, palSize, 1, 1)
            let bytesPerRow = palSize * pixSize
            let palBytes = getPal(palSize)
            palTex.replace(region: palRegion,
                           mipmapLevel: 0,
                           withBytes: palBytes,
                           bytesPerRow: bytesPerRow)
        }
        plane˚?.updateMtlBuffer()
    }

    override public func computeNode(_ computeEnc: MTLComputeCommandEncoder)  {

        computeEnc.setTexture(inTex˚,  index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        computeEnc.setTexture(palTex˚, index: 2)
        computeEnc.setBuffer (plane˚,  index: 0)
        super.computeNode(computeEnc)
        outTex˚?.activate(from: outTex˚)
        palTex˚?.activate(from: palTex˚)
    }
}

public typealias DrawTextureFunc = ((_ bytes: UnsafeMutablePointer<UInt32>,
                                     _ size: CGSize)->(Bool))

public typealias GetTextureFunc = ((_ size: Int) -> (UnsafeMutablePointer<UInt32>))
