//  WaveNode.swift
//  WinSky Waves subsystem port (Port/B3.waves.notes.md).
//
//  Dispatches `cell.wave.metal`'s `waveKernel` as a 1D SCATTER over `num`
//  points (one thread per point), reading/writing pipe.cell.out IN PLACE
//  (access::read_write texture(0)) — NOT the fixed 16×16 full-frame gather
//  dispatch used by CellNode (see B3 §1/§5.1). Audio taps (buffer(1)=mag,
//  buffer(2)=fft) default to a silent zero buffer (magCount/fftCount == 0)
//  so the node compiles and runs before any AmplitudeTap/FFTTap shim lands
//  (B3 §6, Port/Stubs.md gaps 1–2).

import Foundation
import Metal
import QuartzCore
import MuFlo

public class WaveNode: ComputeNode {

    // WaveUniforms mirror (buffer(0), 44 bytes, 11×Float32 — order is authoritative)
    // [algo, t, num, ux, uy, ur, ua, seed, selectT, magCount, fftCount]
    private var outTex˚ : Flo?
    private var algo˚   : Flo?
    private var uxyn˚   : Flo?    // (x: ux, y: uy, z: num) single leafXYZ
    private var ur˚     : Flo?
    private var ua˚     : Flo?
    private var seed˚   : Flo?

    private let startTime = CACurrentMediaTime()
    private var lastAlgo  = Float.nan
    private var selectT   = Float(0)
    private var seedBump  = Float(0)

    // audio taps — silent 1-element zero buffers (count 0) unless a live
    // provider is injected. `audioTap` keeps WaveNode decoupled from MuAudio
    // (no package dependency edge): the app wires it at startup, e.g.
    // `WaveNode.audioTap = { (muAudio.micTap.mag, muAudio.micTap.fft) }` —
    // driven by the `mic.input` leaf (y volume gates the mic, x band-pass)
    nonisolated(unsafe) public static var audioTap: (@Sendable () -> (mag: [Float], fft: [Float]))?
    private var magBuf: [Float] = [0]
    private var fftBuf: [Float] = [0]

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        super.init(pipeline, pipeFlo˚)
        outTex˚ = pipeFlo˚.superBindPath("out")   // shared pipe.cell.out
        algo˚   = pipeFlo˚.findPath("algo")
        uxyn˚   = pipeFlo˚.findPath("uxyn")
        ur˚     = pipeFlo˚.findPath("ur")
        ua˚     = pipeFlo˚.findPath("ua")
        seed˚   = pipeFlo˚.findPath("seed")

        shader = Shader(pipeline, "cell.wave", kernel: "waveKernel")
    }

    public override func makeResources() {
        // ensure the shared scatter target exists even if no CellNode ran
        computeTexture(outTex˚)
        super.makeResources()
        outTex˚?.reactivate()
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {

        guard let mtlCompute,
              let outTex = outTex˚?.texture else { return }

        let t    = Float(CACurrentMediaTime() - startTime)
        let algo = algo˚?.float ?? 0
        if algo != lastAlgo {           // reroll-on-select: latch selectT, bump seed
            lastAlgo = algo
            selectT  = t
            seedBump += 1
        }
        let uxyn = uxyn˚?.xyz ?? SIMD3<Float>(0, 0, 100)
        let num = max(1, Int(uxyn.z))

        if let audioTap = Self.audioTap {  // live mic: pull per frame
            let (mag, fft) = audioTap()
            magBuf = mag.isEmpty ? [0] : mag
            fftBuf = fft.isEmpty ? [0] : fft
        }
        let magCount = magBuf.count > 1 ? magBuf.count : 0 // 1-element zero = silent contract
        let fftCount = fftBuf.count > 1 ? fftBuf.count : 0

        let u: [Float] = [
            algo,                          // algo
            t,                             // t
            Float(num),                    // num (uxyn.z)
            uxyn.x,                        // ux
            uxyn.y,                        // uy
            ur˚?.float ?? 0,               // ur
            ua˚?.float ?? 0,               // ua
            (seed˚?.float ?? 0) + seedBump,// seed
            selectT,                       // selectT
            Float(magCount),               // magCount (0 = silent)
            Float(fftCount) ]              // fftCount (0 = silent)

        encoder.setComputePipelineState(mtlCompute)
        // same texture on read(0) and write(1): split-slot in-place scatter,
        // because bgra8Unorm forbids a single access::read_write argument
        encoder.setTexture(outTex, index: 0)
        encoder.setTexture(outTex, index: 1)
        u.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                encoder.setBytes(base, length: raw.count, index: 0)
            }
        }
        magBuf.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                encoder.setBytes(base, length: raw.count, index: 1)
            }
        }
        fftBuf.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                encoder.setBytes(base, length: raw.count, index: 2)
            }
        }
        // uniform threadgroups: dispatchThreads (non-uniform) is unsupported on
        // simulator/older feature sets; kernel guards gid >= num for the round-up
        let tgWidth = min(num, mtlCompute.maxTotalThreadsPerThreadgroup)
        let groups = (num + tgWidth - 1) / tgWidth
        encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: tgWidth, height: 1, depth: 1))
    }

    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {
        let outAdr = outTex˚?.texPtr ?? ""
        super.logShader(&logging, "(⟲\(outAdr))") // in-place scatter, no ping-pong
    }
}
