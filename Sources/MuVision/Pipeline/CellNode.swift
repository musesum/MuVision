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
                         _ pipeFlo˚ : Flo) {

        super.init(pipeline, pipeFlo˚)
        fakeTex˚ = pipeFlo˚.superBindPath("fake")
        realTex˚ = pipeFlo˚.superBindPath("real")
        outTex˚  = pipeFlo˚.superBindPath("out")
        version˚ = pipeFlo˚.superBindPath("version")
        loops˚   = pipeFlo˚.superBindPath("loops")

        switch pipeFlo˚.name {
        case "slide": shader = Shader(pipeline, file: "cell.rule.slide", kernel: "slideKernel")
        case "zha"  : shader = Shader(pipeline, file: "cell.rule.zha",   kernel: "zhaKernel" )
        case "ave"  : shader = Shader(pipeline, file: "cell.rule.ave",   kernel: "aveKernel" )
        case "fade" : shader = Shader(pipeline, file: "cell.rule.fade",  kernel: "fadeKernel")
        case "melt" : shader = Shader(pipeline, file: "cell.rule.melt",  kernel: "meltKernel")
        case "tunl" : shader = Shader(pipeline, file: "cell.rule.tunl",  kernel: "tunlKernel")
        case "fred" : shader = Shader(pipeline, file: "cell.rule.fred",  kernel: "fredKernel")
        default:  PrintLog("⁉️ CellNode:: unknown shader named: \(pipeFlo˚.name)")
        }
        loops˚?.addClosure { flo, _ in
            self.loops = flo.int
        }
        loops˚?.reactivate()
    }

    public override func makeResources() {

        computeTexture(outTex˚)
        super.makeResources()
        outTex˚?.reactivate()
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {
        version˚?.updateMtlBuffer()
        encoder.setBuffer (version˚, index: 0)
        encoder.setTexture(realTex˚, index: 0)
        encoder.setTexture(outTex˚,  index: 1)
        super.computeShader(encoder)

        let loopi = Int(loops)
        if loopi > 0 {
            for counter in 1 ... Int(loops) {
                encoder.setTexture(fakeTex˚, index: (counter + 0) % 2)
                encoder.setTexture(outTex˚,  index: (counter + 1) % 2)
                super.computeShader(encoder)
            }
        }
        outTex˚?.reactivate()
    }
    public override func logShader( _ logging: inout String,
                                    _ inOut: String) {
        let inAdr = fakeTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr)⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }

}
