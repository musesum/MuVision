import Metal
import UIKit
import MuFlo
import simd

public class CameraNode: ComputeNode {

    private var camera˚   : Flo?
    private var outTex˚   : Flo?
    private var front˚    : Flo?

#if !os(visionOS)
    override public init(_ pipeline : Pipeline,
                         _ pipeFlo  : Flo) {

        super.init(pipeline, pipeFlo)
        camera˚ = pipeFlo
        outTex˚ = pipeFlo.superBindPath("out")
        front˚  = pipeFlo.superBindPath("front")
        shader  = Shader(pipeline, file: "pipe.camera", kernel: "cameraKernel")
        front˚?.addClosure { flo,_ in
            CameraSession.shared.facing(flo.bool)
        }
        makeResources()
    }

    override open func makeResources() {
        camera˚?.addClosure { flo,_ in
            if let val = flo.val("on") {
                let isOn = val > 0
                CameraSession.shared.setCameraOn(isOn)
            }
        }
        super.makeResources()
    }
    
    public override func computeNode(_ computeEnc: MTLComputeCommandEncoder)  {

        guard CameraSession.shared.hasNewTex else { return }
        guard let camTex = CameraSession.shared.cameraTex else { return }
        pipeline.updateTexture(self, outTex˚, rotate: false)
        computeEnc.setTexture(camTex, index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        super.computeNode(computeEnc)
        outTex˚?.activate(from: outTex˚)
    }
#endif
}
