//  FieldNode.swift
//  WinSky Field subsystem port (Port/B4.fields.notes.md).
//
//  Two-kernel warp: `fieldMapKernel` bakes a per-pixel source-coordinate map
//  into an rg32Float texture and is re-dispatched ONLY when algo / a[] / seed
//  change (B4 §2); `fieldApplyKernel` runs every frame, warping prevTex
//  (pipe.cell.real) through the map and blending into outTex (pipe.cell.out).
//  FieldUniforms (buffer(0), 80 bytes) is shared by both kernels; a[] setup
//  constants are computed HOST-side once per regen (B4 §4.2).

import Foundation
import Metal
import MuFlo

public class FieldNode: ComputeNode {

    private var realTex˚ : Flo?   // pipe.cell.real  (incoming/feedback)
    private var outTex˚  : Flo?   // pipe.cell.out   (next)
    /// consolidated xyzw param node (2026-07-11): x algo, y fader,
    /// z a0 override, w a1 override (0 ⇒ use computed). The seed CONTROL is
    /// retired — fields run at the fixed default seed (kernel + host rnd
    /// paths unchanged, same output as the old seed=1 default)
    private var algo˚    : Flo?
    private static let fixedSeed = UInt32(1)

    private var mapShader   : Shader?
    private var applyShader : Shader?
    private var mapPipe   : MTLComputePipelineState?
    private var applyPipe : MTLComputePipelineState?
    private var mapTex    : MTLTexture?

    private var uniformBytes = [UInt8](repeating: 0, count: 80)
    private var aConst = [Float](repeating: 0, count: 16)

    private var needsMap = true
    private var lastAlgo = Int(-1)
    private var lastA0   = Float.nan
    private var lastA1   = Float.nan

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        super.init(pipeline, pipeFlo˚)
        realTex˚ = pipeFlo˚.superBindPath("real")
        outTex˚  = pipeFlo˚.superBindPath("out")
        algo˚    = pipeFlo˚.findPath("algo")

        mapShader   = Shader(pipeline, "cell.field", kernel: "fieldMapKernel")
        applyShader = Shader(pipeline, "cell.field", kernel: "fieldApplyKernel")
        pipeline.resizeNodes.append { [weak self] in self?.makeMapTex() }
    }

    /// rg32Float source-coordinate map, same grid as the cell chain; remade on pipe size change
    func makeMapTex() {
        let td = MTLTextureDescriptor()
        td.pixelFormat = .rg32Float
        td.width  = Int(pipeline.pipeSize.width)
        td.height = Int(pipeline.pipeSize.height)
        td.usage  = [.shaderRead, .shaderWrite]
        mapTex = pipeline.device.makeTexture(descriptor: td)
        mapTex?.label = pipeFlo˚.path(3) + ".map"
    }

    public override func makeResources() {

        setupThreadGroup()                 // full-grid 16×16 dispatch (ComputeNode)
        computeTexture(outTex˚)            // ensure shared pipe.cell.out exists

        if let fn = mapShader?.kernelFunction {
            mapPipe = try? pipeline.device.makeComputePipelineState(function: fn)
        }
        if let fn = applyShader?.kernelFunction {
            applyPipe = try? pipeline.device.makeComputePipelineState(function: fn)
        }
        makeMapTex()

        outTex˚?.reactivate()
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {

        guard let applyPipe,
              let mapPipe,
              let mapTex,
              let outTex  = outTex˚?.texture,
              let prevTex = realTex˚?.texture else { return }

        let algo = Int(algo˚?.val("x") ?? 0)
        let a0   = Float(algo˚?.val("z") ?? 0)
        let a1   = Float(algo˚?.val("w") ?? 0)
        let fadeGain = Float(algo˚?.val("y") ?? 10000) / 10000

        if algo != lastAlgo || a0 != lastA0 || a1 != lastA1 {
            lastAlgo = algo; lastA0 = a0; lastA1 = a1
            computeAConstants(algo, Self.fixedSeed)
            if a0 != 0 { aConst[0] = a0 }
            if a1 != 0 { aConst[1] = a1 }
            needsMap = true
        }
        packUniforms(algo: algo, seed: Self.fixedSeed, fadeGain: fadeGain)

        if needsMap {
            needsMap = false
            encoder.setComputePipelineState(mapPipe)
            encoder.setTexture(mapTex, index: 0)
            bindUniforms(encoder)
            encoder.dispatchThreadgroups(threadCount, threadsPerThreadgroup: threadSize)
        }
        encoder.setComputePipelineState(applyPipe)
        encoder.setTexture(mapTex,  index: 0)
        encoder.setTexture(prevTex, index: 1)
        encoder.setTexture(outTex,  index: 2)
        bindUniforms(encoder)
        encoder.dispatchThreadgroups(threadCount, threadsPerThreadgroup: threadSize)

        outTex˚?.reactivate()
    }

    // MARK: - FieldUniforms packing (80 bytes: u32 algo, u32 seed, f32 fadeGain, f32 pad, f32 a[16])

    private func packUniforms(algo: Int, seed: UInt32, fadeGain: Float) {
        uniformBytes.withUnsafeMutableBytes { p in
            p.storeBytes(of: UInt32(max(0, algo)), toByteOffset: 0, as: UInt32.self)
            p.storeBytes(of: seed,                 toByteOffset: 4, as: UInt32.self)
            p.storeBytes(of: fadeGain,             toByteOffset: 8, as: Float.self)
            p.storeBytes(of: Float(0),             toByteOffset: 12, as: Float.self)
            for i in 0 ..< 16 {
                p.storeBytes(of: aConst[i], toByteOffset: 16 + i * 4, as: Float.self)
            }
        }
    }
    private func bindUniforms(_ encoder: MTLComputeCommandEncoder) {
        uniformBytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                encoder.setBytes(base, length: raw.count, index: 0)
            }
        }
    }

    // MARK: - host a[] setup (B4 §4.2, run once per regen)

    private func fieldHashU(_ x0: UInt32) -> UInt32 {
        var x = x0
        x ^= x >> 16; x = x &* 0x7feb352d
        x ^= x >> 15; x = x &* 0x846ca68b
        x ^= x >> 16; return x
    }
    private func rnd(_ algo: UInt32, _ seed: UInt32, _ i: UInt32, _ range: Double) -> Double {
        let key = seed ^ (algo &* 0x9E37_79B9) ^ (i &* 0x27D4_EB2F)
        return (Double(fieldHashU(key)) / 4294967296.0) * range
    }
    private func computeAConstants(_ algo: Int, _ seed: UInt32) {
        var a = [Float](repeating: 0, count: 16)
        let g = UInt32(max(0, algo))
        func r(_ i: UInt32, _ range: Double) -> Double { rnd(g, seed, i, range) }
        switch algo {
        case 1:  a[0] = 0.0625; a[1] = 16.8
        case 3:  a[0] = Float(r(0,10)+15); a[1] = Float(1-r(1,0.0001)); a[2] = Float(0.003+r(2,0.003))
        case 6:  a[0] = 32; a[1] = 0.01
        case 7:  a[0] = 120.113; a[1] = Float(1+r(1,0.146517)); a[2] = a[0]/a[1]
        case 8:  a[0] = -1.1883951
        case 9:  a[0] = Float(r(0,0.004)+0.004); a[1] = Float(r(1,200)+50)
        case 12: a[0] = Float(r(0,31.4)+12.56); a[1] = Float(r(1,0.0628)+0.0314)
        case 13: a[0] = Float(r(0,0.004)+0.002); a[1] = Float(r(1,30)+8); a[2] = Float(r(2,16)+4); a[3] = Float(2*Double.pi)*a[2]
        case 14: a[0] = Float(8+trunc(r(0,7.5))); a[1] = Float(r(1,0.05)-0.075)
        case 15: a[0] = Float(r(0,0.05)+0.001); a[1] = Float(r(1,40)+5); a[2] = Float(r(2,0.05)+0.01)
        case 16: a[0] = Float((r(0,0.2)-0.1) < 0 ? -1 : 1)
        case 19: a[0] = Float(r(0,100)+2)
        case 20: a[0] = Float(1.0/0.7)
        case 21: a[0] = Float(r(0,28)); a[1] = Float(r(1,0.07536)); a[2] = Float(4.39749*r(2,6.28)); a[3] = Float(r(3,0.1256))
        case 23: a[0] = Float(1.0/sin(0.1)); a[1] = Float(cos(0.630))
        default: break
        }
        aConst = a
    }

    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {
        let inAdr = realTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        super.logShader(&logging, "(\(inAdr)⟶\(outAdr))")
    }
}
