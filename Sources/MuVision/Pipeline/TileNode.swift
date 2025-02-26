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
                         _ childFlo : Flo) {

        super.init(pipeline, childFlo)

        inTex˚  = pipeFlo.superBindPath("in")
        outTex˚ = pipeFlo.superBindPath("out")
        repeat˚ = pipeFlo.superBindPath("repeat")
        mirror˚ = pipeFlo.superBindPath("mirror")
        shader  = Shader(pipeline, file: "kernel.tile", kernel: "tileKernel")
        makeResources()
    }

    public override func makeResources() {

        pipeline.updateTexture(self, outTex˚)
        super.makeResources()
    }
    
    override public func computeNode(_ computeEnc: MTLComputeCommandEncoder)  {

        repeat˚?.updateMtlBuffer()
        mirror˚?.updateMtlBuffer()

        computeEnc.setTexture(inTex˚,   index: 0)
        computeEnc.setTexture(outTex˚,  index: 1)
        computeEnc.setBuffer (repeat˚,  index: 0)
        computeEnc.setBuffer (mirror˚,  index: 1)
        super.computeNode(computeEnc)
        outTex˚?.activate(from: outTex˚)
    }


}
