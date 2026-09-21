// created by musesum on 6/26/24

import Metal
import MetalKit
import QuartzCore
import MuFlo

open class RenderNode: PipeNode {
    public var renderPipelineState: MTLRenderPipelineState?

    /// tracking-areas twins, keyed by fragment name and attachment; a nil value is one that failed to build
    private var areaStates = [String: MTLRenderPipelineState?]()

    /// the twin of one render state matching the pass being encoded: it declares the
    /// tracking-areas attachment when the drawable carries the textures, and the same
    /// shaders without it otherwise (a capture drawable). Made on the frame that first
    /// asks for it; nil while no layer configured a format, so the caller keeps its
    /// plain state, and nil for a writing twin on a pass without the attachment
    public func areaState(_ file: String,
                          vertex: String,
                          fragment: String,
                          _ metalVD: MTLVertexDescriptor = MTLVertexDescriptor(),
                          writes: Bool = false) -> MTLRenderPipelineState? {

        guard let areas = TrackingAreas.format else { return nil }
        let attached = TrackingAreas.passAreas
        if writes && !attached { return nil }
        let key = attached ? fragment : fragment + "/plain"
        if let made = areaStates[key] { return made }
        let made = makeRenderState(metalVD,
                                   Shader(pipeline, file, vertex: vertex, fragment: fragment),
                                   areas: attached ? areas : nil, writes: writes)
        areaStates[key] = made
        return made
    }
}
