//  created by musesum on 4/4/23.

import Metal
import MuFlo

open class TileNode: ComputeNode {
    
    private var tileTex: MTLTexture?

    private var inTex˚  : Flo?
    private var outTex˚ : Flo?
    private var repeat˚ : Flo?
    private var mirror˚ : Flo?

    override public init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        super.init(pipeline, pipeNode˚)

        inTex˚  = pipeNode˚.superBindPath("in")
        outTex˚ = pipeNode˚.superBindPath("out")
        repeat˚ = pipeNode˚.superBindPath("repeat")
        mirror˚ = pipeNode˚.superBindPath("mirror")
        shader  = Shader(pipeline, "kernel.tile", kernel: "tileKernel")
    }

    public override func makeResources() {

        computeTexture(outTex˚)
        super.makeResources()
    }
    
    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {

        repeat˚?.updateMtlBuffer()
        mirror˚?.updateMtlBuffer()

        encoder.setTexture(inTex˚,  index: 0)
        encoder.setTexture(outTex˚, index: 1)
        encoder.setBuffer (repeat˚, index: 0)
        encoder.setBuffer (mirror˚, index: 1)
        super.computeShader(encoder)
        outTex˚?.reactivate()
    }
    
    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {

        let inAdr = inTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr)⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }

    /// screen fraction u → fraction of tile.in (the texture tileKernel gathered from);
    /// mirrors tileKernel exactly so a dot drawn at the mapped point shows up under the
    /// touch in every tile. Reads the uploaded buffers, the values the frame's dispatch
    /// used, not the flo (which can lag one frame while canvas.repeat animates).
    public func sourceFraction(_ u: SIMD2<Float>) -> SIMD2<Float> {
        guard pipeFlo˚.val("on") ?? 0 > 0,
              let repBuf = repeat˚?.buffer, let mirBuf = mirror˚?.buffer else { return u }
        let rep2 = repBuf.contents().bindMemory(to: Float.self, capacity: 2)
        let mir2 = mirBuf.contents().bindMemory(to: Float.self, capacity: 2)
        func fold(_ g: Float, _ r: Float, _ m: Float) -> Float {
            let rep = max(0.005, 1 - r)
            let period = rep * (1 + m)
            var t = g.truncatingRemainder(dividingBy: period)
            if t < 0 { t += period }          // fmod matches C sign; g is expected >= 0
            if t > rep { t = (period - t) / max(0.0001, m) }
            return t / rep
        }
        return SIMD2(fold(u.x, rep2[0], mir2[0]), fold(u.y, rep2[1], mir2[1]))
    }
}

