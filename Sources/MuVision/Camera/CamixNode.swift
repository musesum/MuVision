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
    public override func computeShader(_ computeEnc: MTLComputeCommandEncoder)  {
        
        guard camera.hasNewTex else { return }
        mixcam˚?.updateMtlBuffer()
        computeEnc.setTexture(inTex˚,  index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        computeEnc.setTexture(camTex˚, index: 3)
        computeEnc.setBuffer (mixcam˚, index: 0)
        super.computeShader(computeEnc)
        outTex˚?.reactivate()
    }
#endif
}

