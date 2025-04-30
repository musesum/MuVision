// created by musesum on 1/9/24

import MetalKit

/// immersed DisplayLayer will changes stencil and cull requirements
public enum RenderState: String {
    case windowed
    case immersed
    public var script: String { return rawValue }
}

public class RenderDepth {

    var cull    : MTLCullMode
    var winding : MTLWinding
    var compare : MTLCompareFunction
    var write   : Bool

    public init(_ cull    : MTLCullMode,
                _ winding : MTLWinding,
                _ compare : MTLCompareFunction,
                _ write   : Bool) {

        self.cull    = cull
        self.winding = winding
        self.compare = compare
        self.write   = write
    }
}

public class DepthRendering {

    var immersed : RenderDepth
    var windowed : RenderDepth
    var renderState : RenderState
    var stencil : MTLDepthStencilState!

    public init(_ immersed : RenderDepth,
                _ windowed : RenderDepth,
                _ renderState : RenderState) {

        self.immersed = immersed
        self.windowed = windowed
        self.renderState = renderState
        makeStencil(renderState)
    }

    func makeStencil(_ renderState: RenderState) {

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let depth = MTLDepthStencilDescriptor()

        switch renderState {

        case .immersed:
            depth.depthCompareFunction = immersed.compare
            depth.isDepthWriteEnabled = immersed.write

        case .windowed:
            depth.depthCompareFunction = windowed.compare
            depth.isDepthWriteEnabled = windowed.write
        }
        stencil = device.makeDepthStencilState(descriptor: depth)!
    }
    public func setCullWindingStencil(_ renderEnc: MTLRenderCommandEncoder,
                                      _ renderState: RenderState) {

        if self.renderState != renderState {
            self.renderState = renderState
            makeStencil(renderState)
        }
        renderEnc.setDepthStencilState(stencil)

        switch renderState {
        case .immersed:
            renderEnc.setCullMode(immersed.cull)
            renderEnc.setFrontFacing(immersed.winding)

        case .windowed:
            renderEnc.setCullMode(windowed.cull)
            renderEnc.setFrontFacing(windowed.winding)
        }
    }
}
