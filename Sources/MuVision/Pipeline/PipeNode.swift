
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

    public func runCompute(_ computeEnc: MTLComputeCommandEncoder,
                           _ logging: inout String) {
        
        if let node = self as? ComputeNode {
            logging += node.pipeName + " -> "
            node.updateFirstTime()
            node.updateUniforms()
            node.computeShader(computeEnc)
        }
        pipeChildren
            .filter { $0.pipeFlo˚.val("on") ?? 0 > 0 }
            .forEach { $0.runCompute(computeEnc, &logging) }
    }

    public func runRender(_ renderEnc: MTLRenderCommandEncoder,
                          _ logging: inout String) {

            if let node = self as? RenderNode {
                logging += node.pipeName + " -> "
                updateFirstTime()
                node.updateUniforms()
                node.renderShader(renderEnc, pipeline.renderState)
            }
        pipeChildren
            .filter { $0.pipeFlo˚.val("on") ?? 0 > 0 }
            .forEach { $0.runRender(renderEnc, &logging) }
    }
#if os(visionOS)
    open func updateUniforms(_ : LayerRenderer.Drawable,
                             _ : DeviceAnchor?) {}

    public func runRender(_ renderEnc : MTLRenderCommandEncoder,
                          _ drawable  : LayerRenderer.Drawable,
                          _ anchor    : DeviceAnchor?,
                          _ logging   : inout String) {

        if let node = self as? RenderNode {
            logging += node.pipeName + " -> "
            updateFirstTime()
            node.updateUniforms(drawable, anchor)
            node.renderShader(renderEnc, pipeline.renderState)
        }
        pipeChildren
            .filter { $0.pipeFlo˚.val("on") ?? 0 > 0 }
            .forEach { $0.runRender(renderEnc, drawable, anchor, &logging) }
    }
#endif


    
    public static func == (lhs: PipeNode, rhs: PipeNode) -> Bool { return lhs.id == rhs.id }

    open func updateUniforms() {}
    open func makeResources() {}
    open func makePipeline() {}
    open func renderShader(_: MTLRenderCommandEncoder, _: RenderState) {}

    private func updateFirstTime() {
        if firstTime {
            firstTime = false
            makePipeline()
            makeResources()
        }
    }

}

