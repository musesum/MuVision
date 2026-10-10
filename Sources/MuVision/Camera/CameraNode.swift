import Metal
import UIKit
import MuFlo
import simd

@available(iOS 18.0, *)
public class CameraNode: ComputeNode {

    private var camera˚ : Flo?
    private var outTex˚ : Flo?
    private var front˚  : Flo?
    private var zoom˚   : Flo?
    private var mask˚   : Flo?   // subject mask, aspect-filled like the frame
    private var maskShader : Shader?
    private var maskCompute: MTLComputePipelineState?
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
        zoom˚   = pipeNode˚.superBindPath("zoom")
        mask˚   = pipeNode˚.findPath("mask")
        shader  = Shader(pipeline, "pipe.camera", kernel: "cameraKernel")
        if mask˚ != nil {
            maskShader = Shader(pipeline, "pipe.camera", kernel: "cameraMaskKernel")
        }

        front˚?.addClosure { flo,_ in
            camera.facing(flo.bool)
        }
        zoom˚?.addClosure { flo,_ in
            if let x = flo.val("x") {
                camera.setZoomFactor(CGFloat(x))
            }
        }
        // registered in init, not makeResources: makeResources only runs after
        // `on > 0` passes the pipeChildren filter, so a closure added there
        // misses the menu tap that turned the camera on (3-tap bug)
        camera˚?.addClosure { flo,_ in
            if let val = flo.val("on") {
                let isOn = val > 0
                camera.setCameraOn(isOn)
            }
        }
        camera˚?.reactivate()
        // a restored session: the Snapshot merged `on 1` into pipe.camera
        // before this node existed, so no closure saw it. Start from the
        // value as it stands; otherwise camera.stream reads on while nothing
        // streams, and the Layers leaf, seeing the stream already on, never
        // turns it on again
        if (camera˚?.val("on") ?? 0) > 0 {
            camera.setCameraOn(true)
        }
    }

    public override func makeResources() {
        super.makeResources()
        if let fn = maskShader?.kernelFunction {
            maskCompute = try? pipeline.device.makeComputePipelineState(function: fn)
        }
    }

    public override func computeShader(_ encoder: MTLComputeCommandEncoder)
    {
        guard camera.hasNewTex else { return }
        guard let camTex = camera.cameraTex else { return }
        computeTexture(outTex˚)
        outTex˚?.activate() // camera will override real texture
        encoder.setTexture(camTex, index: 0)
        encoder.setTexture(outTex˚, index: 1)
        super.computeShader(encoder)
        // the mask takes the frame's center-crop, sampled by uv over the whole frame
        if let maskTex = camera.maskTex, let mask˚, let maskCompute {
            computeTexture(mask˚)
            encoder.setComputePipelineState(maskCompute)
            encoder.setTexture(maskTex, index: 0)
            encoder.setTexture(mask˚,   index: 1)
            encoder.setTexture(camTex,  index: 2)
            encoder.dispatchThreadgroups(threadCount, threadsPerThreadgroup: threadSize)
            mask˚.activate()
        }
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
