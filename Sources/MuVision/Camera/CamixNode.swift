// created by musesum on 7/17/24

import Metal
import UIKit
import MuFlo

public class CamixNode: ComputeNode {

    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var camTex˚ : Flo?
    private var mixcam˚ : Flo?
    private var frame˚  : Flo?
    private var front˚  : Flo?

    override public init(_ pipeline : Pipeline,
                         _ childFlo : Flo) {

        super.init(pipeline, childFlo)

        inTex˚  = pipeFlo.superBindPath("in")
        camTex˚ = pipeFlo.superBindPath("cam")
        outTex˚ = pipeFlo.superBindPath("out")
        mixcam˚ = pipeFlo.superBindPath("mixcam")
        frame˚  = pipeFlo.superBindPath("frame")
        shader  = Shader(pipeline, file: "pipe.camix", kernel: "camixKernel")
        makeResources()
    }

    public override func makeResources() {

        pipeline.updateTexture(self, outTex˚)
        super.makeResources()
    }
#if !os(visionOS)
    public override func computeNode(_ computeEnc: MTLComputeCommandEncoder)  {

        guard CameraSession.shared.hasNewTex else { return }

        if frame˚?.texture == nil,
           let camTex = CameraSession.shared.cameraTex,
           let outTex = outTex˚?.texture,
           let frame = texClip(in: camTex, out: outTex) {
            frame˚?.updateFloScalars(frame)
        }

        mixcam˚?.updateMtlBuffer()
        computeEnc.setTexture(inTex˚,  index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        computeEnc.setTexture(camTex˚, index: 3)
        computeEnc.setBuffer (mixcam˚, index: 0)
        computeEnc.setBuffer (frame˚,  index: 1)
        super.computeNode(computeEnc)
        outTex˚?.activate(from: outTex˚)
    }
#endif
}

