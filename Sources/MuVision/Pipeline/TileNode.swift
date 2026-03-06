//  created by musesum on 4/4/23.

import Metal
import MuFlo

open class TileNode: ComputeNode {
    
    private var tileTex: MTLTexture?

    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var repeat˚ : Flo?
    private var mirror˚ : Flo?

    override public init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        super.init(pipeline, pipeNode˚)

        inTex˚  = pipeNode˚.superBindPath("in")
        outTex˚ = pipeNode˚.superBindPath("out")
        repeat˚ = pipeNode˚.superBindPath("repeat")
        mirror˚ = pipeNode˚.superBindPath("mirror")
        shader  = Shader(pipeline, file: "kernel.tile", kernel: "tileKernel")
    }

    public override func makeResources() {

        computeTexture(outTex˚)
        super.makeResources()
    }
    
    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {

        repeat˚?.updateMtlBuffer()
        mirror˚?.updateMtlBuffer()

        encoder.setTexture(inTex˚,  index: 0)
        encoder.setTexture(outTex˚, index: 1)
        encoder.setBuffer (repeat˚, index: 0)
        encoder.setBuffer (mirror˚, index: 1)
        super.computeShader(encoder)
        outTex˚?.reactivate()
    }
    
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {

        let inAdr = inTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr)⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }
}

