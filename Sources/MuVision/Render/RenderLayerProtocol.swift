// created by musesum.
import Metal

public protocol RenderMetalProtocol {
    func makeResources()
    func updateUniforms(_ : MTLDrawable)
    func runLayer(_ : MTLDrawable, _ : MTLCommandBuffer)
}
