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
    private var reseed˚  : Flo?   // warren rows 10/11 entry pulse; nil for every other rule
    private var frame = 0

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        super.init(pipeline, pipeFlo˚)
        fakeTex˚ = pipeFlo˚.superBindPath("fake")
        realTex˚ = pipeFlo˚.superBindPath("real")
        outTex˚  = pipeFlo˚.superBindPath("out")
        version˚ = pipeFlo˚.superBindPath("version")
        loops˚   = pipeFlo˚.superBindPath("loops")
        let name = pipeFlo˚.name
        if name == "warren" { reseed˚ = pipeFlo˚.superBindPath("reseed") }   // only rule with the leaf
        switch name {
        case "slide" : shader = Shader(pipeline, "cell.rule.slide",  kernel: "slideKernel" )
        case "zha"   : shader = Shader(pipeline, "cell.rule.zha",    kernel: "zhaKernel"   )
        case "ave"   : shader = Shader(pipeline, "cell.rule.ave",    kernel: "aveKernel"   )
        case "fade"  : shader = Shader(pipeline, "cell.rule.fade",   kernel: "fadeKernel"  )
        case "melt"  : shader = Shader(pipeline, "cell.rule.melt",   kernel: "meltKernel"  )
        case "tunl"  : shader = Shader(pipeline, "cell.rule.tunl",   kernel: "tunlKernel"  )
        case "fred"  : shader = Shader(pipeline, "cell.rule.fred",   kernel: "fredKernel"  )
        case "drift" : shader = Shader(pipeline, "cell.rule.drift",  kernel: "driftKernel", counter: true)
        case "warren": shader = Shader(pipeline, "cell.rule.warren", kernel: "warrenKernel")
        case "noise" : shader = Shader(pipeline, "cell.rule.noise",  kernel: "noiseKernel", counter: true)
        default:  PrintLog("⁉️ CellNode:: unknown shader named: \(pipeFlo˚.name)")
        }
        if let loops˚ {
            loops˚.addClosure { flo, _ in
                self.loops = flo.int
            }
            loops = loops˚.int
            loops˚.reactivate()
        }
        if name == "zha" { loops = 10 }
    }

    public override func makeResources() {

        computeTexture(outTex˚)
        super.makeResources()
        outTex˚?.reactivate()
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {
        version˚?.updateMtlBuffer()
        encoder.setBuffer (version˚, index: 0)
        if let reseed˚ {   // index 1 only for the rule that declares the leaf; counter rules keep it
            reseed˚.updateMtlBuffer()
            encoder.setBuffer(reseed˚, index: 1)
        }
        encoder.setTexture(realTex˚, index: 0)
        encoder.setTexture(outTex˚,  index: 1)

        if shader?.counter ?? false {
            var f = Float(frame)
            encoder.setBytes(&f, length: MemoryLayout<Float>.size, index: 1)
        }
        frame += 1
        super.computeShader(encoder)

        let loopi = Int(loops)
        if loopi > 0 {
            for counter in 1 ... loopi {
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
