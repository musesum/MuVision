//  created by musesum on 2/22/19.

import Foundation
import Metal
import MetalKit
import MuFlo

public class CellNode: ComputeNode {

    private var loops˚: Flo?
    private var loops = 0

    private var fakeTex˚ : Flo?
    private var realTex˚ : Flo?
    private var outTex˚  : Flo?
    private var version˚ : Flo?
    private var frame = 0

    override public init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        super.init(pipeline, pipeNode˚)
        fakeTex˚ = pipeNode˚.superBindPath("fake")
        realTex˚ = pipeNode˚.superBindPath("real")
        outTex˚  = pipeNode˚.superBindPath("out")
        version˚ = pipeNode˚.superBindPath("version")
        loops˚   = pipeNode˚.superBindPath("loops")

        switch pipeNode˚.name {
        case "slide": shader = Shader(pipeline, file: "cell.rule.slide", kernel: "slideKernel")
        case "zha"  : shader = Shader(pipeline, file: "cell.rule.zha",   kernel: "zhaKernel" )
        case "ave"  : shader = Shader(pipeline, file: "cell.rule.ave",   kernel: "aveKernel" )
        case "fade" : shader = Shader(pipeline, file: "cell.rule.fade",  kernel: "fadeKernel")
        case "melt" : shader = Shader(pipeline, file: "cell.rule.melt",  kernel: "meltKernel")
        case "tunl" : shader = Shader(pipeline, file: "cell.rule.tunl",  kernel: "tunlKernel")
        case "fred" : shader = Shader(pipeline, file: "cell.rule.fred",  kernel: "fredKernel")
        default:  PrintLog("⁉️ CellNode:: unknown shader named: \(pipeNode˚.name)")
        }
        makeResources()
    }

    public override func makeResources() {

        loops˚?.addClosure { flo, _ in self.loops = flo.int }
        loops˚?.activate()

        pipeline.updateTexture(self, outTex˚)
        super.makeResources()
        outTex˚?.activate(from: outTex˚)
    }

    override public func updateUniforms() {
        super.updateUniforms()
    }

    override public func computeNode(_ computeEnc: MTLComputeCommandEncoder)  {

        version˚?.updateMtlBuffer()

        computeEnc.setBuffer (version˚, index: 0)
        computeEnc.setTexture(realTex˚, index: 0)
        computeEnc.setTexture(outTex˚,  index: 1)
        super.computeNode(computeEnc)

        let loopi = Int(loops)
        if loopi > 0 {
            for counter in 1 ... Int(loops) {
                computeEnc.setTexture(fakeTex˚, index: (counter + 0) % 2)
                computeEnc.setTexture(outTex˚,  index: (counter + 1) % 2)
                super.computeNode(computeEnc)
            }
        }
        outTex˚?.activate(from: outTex˚)
    }
}
