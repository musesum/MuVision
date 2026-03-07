
import Collections
import Metal
import MetalKit
import MuFlo
#if os(visionOS)
import CompositorServices
#endif
public enum ResourceType: String { case unknown, texture, buffer, vertex, fragment }

open class PipeNode: Equatable {
    var id = Visitor.nextId()
    
    public var pipeline: Pipeline
    public var shader: Shader?
    public var pipeName: String
    public var pipeFlo˚: Flo
    public var pipeChildren = [PipeNode]()
    public var firstTime = true

    public init(_ pipeline : Pipeline,
                _ pipeFlo˚ : Flo) {

        self.pipeName = pipeFlo˚.name
        self.pipeline = pipeline
        self.pipeFlo˚ = pipeFlo˚

        pipeFlo˚.children
            .filter { $0.val("on") != nil }
            .forEach { pipeline.makePipeNode($0, self) }
    }

    public func runCompute(_ encoder: MTLComputeCommandEncoder)
    {
        if let node = self as? ComputeNode {
            node.updateFirstTime()
            node.updateUniforms()
            node.computeShader(encoder)
        }
        pipeChildren
            .filter { $0.pipeFlo˚.val("on") ?? 0 > 0 }
            .forEach { $0.runCompute(encoder) }
    }

    public func runRender(_ encoder: MTLRenderCommandEncoder) {
        if let node = self as? RenderNode {
            node.updateFirstTime()
            node.updateUniforms()
            node.renderShader(encoder, pipeline.renderState)
        }
        pipeChildren
            .filter { $0.pipeFlo˚.val("on") ?? 0 > 0 }
            .forEach { $0.runRender(encoder) }
    }
    public func logNode(_ logging: inout String, _ inOut: String) {
        logShader(&logging, inOut)
        pipeChildren
            .filter { $0.pipeFlo˚.val("on") ?? 0 > 0 }
            .forEach { $0.logNode(&logging, inOut) }
    }
    

#if os(visionOS)
    open func updateUniforms(_ : LayerRenderer.Drawable,
                             _ : DeviceAnchor?) {}

    public func runRender(_ encoder  : MTLRenderCommandEncoder,
                          _ drawable : LayerRenderer.Drawable,
                          _ anchor   : DeviceAnchor?) {

        if let node = self as? RenderNode {
            updateFirstTime()
            node.updateUniforms(drawable, anchor)
            node.renderShader(encoder, pipeline.renderState)
        }
        pipeChildren
            .filter { $0.pipeFlo˚.val("on") ?? 0 > 0 }
            .forEach { $0.runRender(encoder, drawable, anchor) }
    }
#endif

    public static func == (lhs: PipeNode, rhs: PipeNode) -> Bool { return lhs.id == rhs.id }

    open func updateUniforms() {}
    open func makeResources() {}
    open func makeShader() {}
    open func renderShader(_: MTLRenderCommandEncoder, _: RenderState) {}

    open func logShader(_ logging: inout String,
                        _ inOut: String) {
        if inOut.isEmpty { return }
        logging += "\(pipeName)\(inOut) ⟹ "
    }

    private func updateFirstTime() {
        if firstTime {
            firstTime = false
            makeShader()
            makeResources()
        }
    }
}

