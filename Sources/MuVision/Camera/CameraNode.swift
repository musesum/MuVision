import Metal
import UIKit
import MuFlo
import simd

public class CameraNode: ComputeNode {

    private var camera˚   : Flo?
    private var outTex˚   : Flo?
    private var front˚    : Flo?
    private let camera: CameraSession
    #if os(visionOS)
    public init(_ pipeline : Pipeline,
                _ pipeNode˚ : Flo,
                _ camera: CameraSession) {
        self.camera = camera
        super.init(pipeline, pipeNode˚)
    }
    #else
    public init(_ pipeline : Pipeline,
                _ pipeNode˚ : Flo,
                _ camera: CameraSession) {

        self.camera = camera
        super.init(pipeline, pipeNode˚)
        camera˚ = pipeNode˚
        outTex˚ = pipeNode˚.superBindPath("out")
        front˚  = pipeNode˚.superBindPath("front")
        shader  = Shader(pipeline, file: "pipe.camera", kernel: "cameraKernel")

        front˚?.addClosure { flo,_ in
            camera.facing(flo.bool)
        }
        makeResources()
    }

    override open func makeResources() {
        camera˚?.addClosure { flo,_ in
            if let val = flo.val("on") {
                let isOn = val > 0
                self.camera.setCameraOn(isOn)
            }
        }
        super.makeResources()
    }
    
    public override func computeShader(_ computeEnc: MTLComputeCommandEncoder)  {

        guard camera.hasNewTex else { return }
        guard let camTex = camera.cameraTex else { return }
        pipeline.updateTexture(self, outTex˚, rotate: false)
        computeEnc.setTexture(camTex, index: 0)
        computeEnc.setTexture(outTex˚, index: 1)
        super.computeShader(computeEnc)
        outTex˚?.activate([],from: outTex˚)
    }
#endif
}
