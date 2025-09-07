// created by musesum on 1/9/24

import MetalKit

/// immersed DisplayLayer will changes stencil and cull requirements
public enum RenderState: String {
    case windowed
    case immersed
    public var script: String { return rawValue }
    public mutating func toggle() {
        if self == .windowed { self = .immersed }
        else                 { self = .windowed }
    }
}

public class RenderDepth {

    var mtlCull    : MTLCullMode
    var mtlWinding : MTLWinding
    var mtlCompare : MTLCompareFunction
    var write      : Bool

    public init(cull    : MTLCullMode,
                winding : MTLWinding,
                compare : MTLCompareFunction,
                write   : Bool) {

        self.mtlCull    = cull
        self.mtlWinding = winding
        self.mtlCompare = compare
        self.write      = write
    }
}

public class DepthRendering {

    var immerseDepth : RenderDepth
    var windowDepth  : RenderDepth
    var renderState  : RenderState
    var mtlDepthStencil : MTLDepthStencilState!

    public init(_ immerseDepth : RenderDepth,
                _ windowDepth  : RenderDepth,
                _ renderState  : RenderState) {

        self.immerseDepth = immerseDepth
        self.windowDepth = windowDepth
        self.renderState = renderState
        makeStencil(renderState)
    }

    func makeStencil(_ renderState: RenderState) {

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let depth = MTLDepthStencilDescriptor()

        switch renderState {

        case .immersed:
            depth.depthCompareFunction = immerseDepth.mtlCompare
            depth.isDepthWriteEnabled = immerseDepth.write

        case .windowed:
            depth.depthCompareFunction = windowDepth.mtlCompare
            depth.isDepthWriteEnabled = windowDepth.write
        }
        mtlDepthStencil = device.makeDepthStencilState(descriptor: depth)!
    }
    public func setCullWindingStencil(_ renderEnc: MTLRenderCommandEncoder,
                                      _ renderState: RenderState) {

        if self.renderState != renderState {
            self.renderState = renderState
            makeStencil(renderState)
        }
        renderEnc.setDepthStencilState(mtlDepthStencil)

        switch renderState {
        case .immersed:
            renderEnc.setCullMode(immerseDepth.mtlCull)
            renderEnc.setFrontFacing(immerseDepth.mtlWinding)

        case .windowed:
            renderEnc.setCullMode(windowDepth.mtlCull)
            renderEnc.setFrontFacing(windowDepth.mtlWinding)
        }
    }
}
