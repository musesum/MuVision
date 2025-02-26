// created by musesum on 1/9/24

import MetalKit

/// immersive DisplayLayer will changes stencil and cull requirements
public enum RenderState: String {
    case passthrough
    case immersive
    public var script: String { return rawValue }
}

public class RenderDepth {

    public static var state: RenderState = .passthrough

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

    var immer   : RenderDepth
    var metal   : RenderDepth
    var state   : RenderState
    var stencil : MTLDepthStencilState!

    public init(immer : RenderDepth,
                metal : RenderDepth) {

        self.immer  = immer
        self.metal  = metal
        self.state = RenderDepth.state
        makeStencil()
    }
    public init(immerse: RenderDepth) {

        RenderDepth.state = .immersive

        self.immer  = immerse
        self.metal  = immerse // not used
        self.state = .immersive
        makeStencil()
    }
    func makeStencil() {

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let depth = MTLDepthStencilDescriptor()

        switch state {

        case .immersive:
            depth.depthCompareFunction = immer.compare
            depth.isDepthWriteEnabled = immer.write

        case .passthrough:
            depth.depthCompareFunction = metal.compare
            depth.isDepthWriteEnabled = metal.write
        }
        stencil = device.makeDepthStencilState(descriptor: depth)!
    }
    public func setCullWindingStencil(_ renderEnc: MTLRenderCommandEncoder) {
        // flipped between .metal and .vision state
        if state != RenderDepth.state {
            state = RenderDepth.state
            makeStencil()
        }
        renderEnc.setDepthStencilState(stencil)

        switch state {
        case .immersive:
            renderEnc.setCullMode(immer.cull)
            renderEnc.setFrontFacing(immer.winding)

        case .passthrough:
            renderEnc.setCullMode(metal.cull)
            renderEnc.setFrontFacing(metal.winding)
        }
    }
}
