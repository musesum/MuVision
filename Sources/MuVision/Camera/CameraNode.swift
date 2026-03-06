import Metal
import UIKit
import MuFlo
import simd

public class CameraNode: ComputeNode {

    private var camera˚ : Flo?
    private var outTex˚ : Flo?
    private var front˚  : Flo?
    private let camera  : CameraSession
    #if os(visionOS)
    public init(_ pipeline  : Pipeline,
                _ pipeNode˚ : Flo,
                _ camera    : CameraSession) {
        self.camera = camera
        super.init(pipeline, pipeNode˚)
    }
    #else
    public init(_ pipeline  : Pipeline,
                _ pipeNode˚ : Flo,
                _ camera    : CameraSession) {

        self.camera = camera
        super.init(pipeline, pipeNode˚)
        camera˚ = pipeNode˚
        outTex˚ = pipeNode˚.superBindPath("out")
        front˚  = pipeNode˚.superBindPath("front")
        shader  = Shader(pipeline, file: "pipe.camera", kernel: "cameraKernel")

        front˚?.addClosure { flo,_ in
            camera.facing(flo.bool)
        }
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
    
    public override func computeShader(_ encoder: MTLComputeCommandEncoder)
    {
        guard camera.hasNewTex else { return }
        guard let camTex = camera.cameraTex else { return }
        computeTexture(outTex˚)
        outTex˚?.activate() //.....
        encoder.setTexture(camTex, index: 0)
        encoder.setTexture(outTex˚, index: 1)
        super.computeShader(encoder)
    }
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {
        guard let camTex = camera.cameraTex else { return }
        let inAdr = camTex.texPtr
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr)⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }

#endif
}
extension MTLTexture {
    var texPtr: String {
        String("\(Unmanaged.passUnretained(self).toOpaque())".suffix(5))
    }
}
