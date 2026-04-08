// created by musesum on 7/17/24

import Metal
import UIKit
import MuFlo

public class CamixNode: ComputeNode {

    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var camTex˚ : Flo?
    private var mixcam˚ : Flo?
    private var camera  : CameraSession

    public init(_ pipeline: Pipeline,
                _ pipeNode˚: Flo,
                _ camera: CameraSession) {

        self.camera = camera
        super.init(pipeline, pipeNode˚)

        inTex˚  = pipeNode˚.superBindPath("in")
        camTex˚ = pipeNode˚.superBindPath("cam")
        outTex˚ = pipeNode˚.superBindPath("out")
        mixcam˚ = pipeNode˚.superBindPath("mixcam")
        shader  = Shader(pipeline, file: "pipe.camix", kernel: "camixKernel")
    }

    public override func makeResources() {

        computeTexture(outTex˚)
        super.makeResources()
    }
#if !os(visionOS)
    public override func computeShader(_ encoder: MTLComputeCommandEncoder)
    {
        guard camera.hasNewTex else { return }
        mixcam˚?.updateMtlBuffer()
        encoder.setTexture(inTex˚,  index: 0)
        encoder.setTexture(outTex˚, index: 1)
        encoder.setTexture(camTex˚, index: 3)
        encoder.setBuffer (mixcam˚, index: 0)
        super.computeShader(encoder)
        outTex˚?.reactivate()
    }
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {

        let inAdr = inTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        let camAdr = camTex˚?.texPtr ?? ""
        let inOut = "((i:\(inAdr),c:\(camAdr))⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }
#endif
}

