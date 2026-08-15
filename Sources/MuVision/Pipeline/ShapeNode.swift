//  ShapeNode.swift
//  Merged procedural-shape rule node: `pipe.cell.rule.shape` runs one of the
//  four shape kernels, selected by its `algo` value (0 simple, 1 zigular →
//  spiralKernel, 2 circular → circleKernel, 3 petal → floralKernel).
//
//  Flattened 2026-07-11: one param node per shape
//  (`simple/zigular/circular/petal`) — no shared cone/column/circle.
//  Touching any param selects its shape: a flo closure on each param node
//  sets `algo` with .fire (user/remote visits only, so archive .bind cannot
//  hijack the active rule), and the pipe `˚algo(-> ..(on 1))` edge
//  solo-activates the shape rule.
//
//  Kernel field sources (on-flags derive from the driving component > 0):
//    spiralKernel  ← zigular : [x>0, x, z, y>0, y]  (x scale, y rays, z strength)
//    circleKernel  ← circular: [x>0, x, w, y>0, y, z]
//    floralKernel  ← petal (single: x spiralz, y num, z petalz, w strength)
//                    into the petal1 block; petal2 and cone/circle/column
//                    fields constant 0 (petals render in isolation)
//    simpleKernel  ← simple.x feeds the version buffer(0) preset when selected;
//                    other kernels take the version buffer and ignore it.

import Foundation
import Metal
import MetalKit
import MuFlo

public class ShapeNode: ComputeNode {

    /// one buffer(1) struct field: a component of a driving flo node,
    /// passed through, collapsed to a 0/1 on-flag, or a constant 0
    private struct Field {
        let node: Int          // index into flos; -1 = constant 0
        let comp: String       // "x" | "y" | "z" | "w"
        let onFlag: Bool       // true → emit (value > 0) ? 1 : 0
    }
    private struct Variant {
        let shader: Shader
        let fields: [Field]    // buffer(1) struct fields, exact kernel order
        var pipeState: MTLComputePipelineState? = nil
    }
    private var variants: [Variant]

    private var fakeTex˚ : Flo?
    private var realTex˚ : Flo?
    private var outTex˚  : Flo?
    private var version˚ : Flo?
    private var algo˚    : Flo?
    private var loops˚   : Flo?
    private var loops = 0

    /// driving param nodes, order fixed: simple, zigular, circular, petal
    private var flos: [Flo?] = []

    private static func f(_ node: Int, _ comp: String, on: Bool = false) -> Field {
        Field(node: node, comp: comp, onFlag: on)
    }
    // node indices into `flos`; `zero` emits a constant 0 field
    private static let simple = 0, zigular = 1, circular = 2, petal = 3
    private static let zero = -1

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        // SpiralUniforms: [cone1On, cone1Scale, cone1Strength, circleOn, circleRays]
        let zigularFields: [Field] = [
            Self.f(Self.zigular, "x", on: true), Self.f(Self.zigular, "x"), Self.f(Self.zigular, "z"),
            Self.f(Self.zigular, "y", on: true), Self.f(Self.zigular, "y"),
        ]
        // CircleUniforms: [cone1On, cone1Scale, cone1Strength, cone2On, cone2Scale, cone2Strength]
        let circularFields: [Field] = [
            Self.f(Self.circular, "x", on: true), Self.f(Self.circular, "x"), Self.f(Self.circular, "w"),
            Self.f(Self.circular, "y", on: true), Self.f(Self.circular, "y"), Self.f(Self.circular, "z"),
        ]
        // FloralUniforms (22 floats): single petal drives the petal1 block
        // (x spiralz, y num, z petalz, w strength); petal2 and the
        // cone/circle/column fields stay constant 0 — petals render alone
        let petalFields: [Field] = [
            Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), Self.f(Self.zero, "x"),  // cone1On, cone1Scale, cone1Strength
            Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), Self.f(Self.zero, "x"),  // cone2On, cone2Scale, cone2Strength
            Self.f(Self.zero, "x"), Self.f(Self.zero, "x"),                          // circleOn, circleRays
            Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), // columnOn, columnNum, columnRays, columnStrength
            Self.f(Self.petal, "y", on: true), Self.f(Self.petal, "y"), Self.f(Self.petal, "x"), Self.f(Self.petal, "z"), Self.f(Self.petal, "w"), // petal1On, petal1Num, petal1Spiralz, petal1Petalz, petal1Strength
            Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), Self.f(Self.zero, "x"), // petal2On, petal2Num, petal2Spiralz, petal2Petalz, petal2Strength
        ]
        variants = [
            Variant(shader: Shader(pipeline, "cell.rule.simple", kernel: "simpleKernel"),
                    fields: []),
            Variant(shader: Shader(pipeline, "cell.rule.spiral", kernel: "spiralKernel"),
                    fields: zigularFields),
            Variant(shader: Shader(pipeline, "cell.rule.circle", kernel: "circleKernel"),
                    fields: circularFields),
            Variant(shader: Shader(pipeline, "cell.rule.floral", kernel: "floralKernel"),
                    fields: petalFields),
        ]
        super.init(pipeline, pipeFlo˚)

        fakeTex˚ = pipeFlo˚.superBindPath("fake")
        realTex˚ = pipeFlo˚.superBindPath("real")
        outTex˚  = pipeFlo˚.superBindPath("out")
        version˚ = pipeFlo˚.superBindPath("version")
        algo˚    = pipeFlo˚.findPath("algo")
        loops˚   = pipeFlo˚.superBindPath("loops")

        flos = ["simple", "zigular", "circular", "petal"].map { pipeFlo˚.findPath($0) }

        // touching a shape's params selects that shape: param → algo (.fire)
        // → ˚algo edge solo-activates the shape rule. Guarded to user/remote
        // visits so archive restore (.bind) cannot hijack the active rule.
        let selects: [(Flo?, Double)] = [
            (flos[Self.simple],   0),
            (flos[Self.zigular],  1),
            (flos[Self.circular], 2),
            (flos[Self.petal],    3),
        ]
        for (flo, index) in selects {
            flo?.addClosure { [weak self] _, visit in
                guard visit.type.has([.user, .remote]) else { return }
                self?.algo˚?.setNameNums([("x", index)], .fire, visit)
            }
        }
        loops˚?.addClosure { flo, _ in
            self.loops = flo.int
        }
        loops˚?.reactivate()
    }

    public override func makeResources() {

        computeTexture(outTex˚)
        if let device = MTLCreateSystemDefaultDevice() {
            for i in variants.indices {
                if let kernelFunction = variants[i].shader.kernelFunction {
                    do {
                        variants[i].pipeState = try device.makeComputePipelineState(function: kernelFunction)
                    } catch {
                        PrintLog("⁉️ ShapeNode::makeResources \(variants[i].shader.kernelName ?? "?") error \(error)")
                    }
                }
            }
        }
        setupThreadGroup()
        outTex˚?.reactivate()
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {

        let index = min(max(Int(algo˚?.float ?? 0), 0), variants.count - 1)
        let variant = variants[index]
        guard let pipeState = variant.pipeState else { return }
        mtlCompute = pipeState

        if index == Self.simple {
            // simpleKernel's preset comes from the shape.simple param
            var preset = Float(flos[Self.simple]?.val("x") ?? 1)
            encoder.setBytes(&preset, length: MemoryLayout<Float>.size, index: 0)
        } else {
            version˚?.updateMtlBuffer()
            encoder.setBuffer (version˚, index: 0)
        }
        encoder.setTexture(realTex˚, index: 0)
        encoder.setTexture(outTex˚,  index: 1)

        if !variant.fields.isEmpty {
            let vals: [Float] = variant.fields.map { field in
                guard field.node >= 0 else { return 0 }
                let v = Float(flos[field.node]?.val(field.comp) ?? 0)
                return field.onFlag ? (v > 0 ? 1 : 0) : v
            }
            vals.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    encoder.setBytes(base, length: raw.count, index: 1)
                }
            }
        }
        super.computeShader(encoder)

        let loopCount = loops // snapshot: flo closure may mutate loops off-encode-thread
        if loopCount > 0 {
            for counter in 1 ... loopCount {
                encoder.setTexture(fakeTex˚, index: (counter + 0) % 2)
                encoder.setTexture(outTex˚,  index: (counter + 1) % 2)
                super.computeShader(encoder)
            }
        }
        outTex˚?.reactivate()
    }

    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {
        let inAdr = fakeTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        super.logShader(&logging, "(\(inAdr)⟶\(outAdr))")
    }
}
