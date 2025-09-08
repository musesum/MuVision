// created by musesum on 6/26/24

import Metal
import MetalKit
import QuartzCore
import MuFlo
#if os(visionOS)
import CompositorServices
#endif

open class RenderNode: PipeNode {

    public var renderPipelineState: MTLRenderPipelineState?
}
