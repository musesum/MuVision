// created by musesum on 1/9/24

import MetalKit

/// immersive DisplayLayer will changes stencil and cull requirements
public enum RenderState: String {
    case metal
    case immer
    public var script: String { return rawValue }
}

public class RenderDepth {

    public static var state: RenderState = .metal

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

    var device      : MTLDevice
    var immer       : RenderDepth
    var metal       : RenderDepth
    var renderState : RenderState
    var stencil     : MTLDepthStencilState!

    public init(_ device: MTLDevice,
                immerse : RenderDepth,
                metal   : RenderDepth) {

        self.device = device
        self.immer  = immerse
        self.metal  = metal
        self.renderState = RenderDepth.state
        makeStencil()
    }
    public init(_ device: MTLDevice,
                immerse: RenderDepth) {

        RenderDepth.state = .immer

        self.device = device
        self.immer  = immerse
        self.metal  = immerse // not used
        self.renderState = .immer
        makeStencil()
    }
    func makeStencil() {

        let depth = MTLDepthStencilDescriptor()

        switch renderState {

        case .immer:
            depth.depthCompareFunction = immer.compare
            depth.isDepthWriteEnabled = immer.write

        case .metal:
            depth.depthCompareFunction = metal.compare
            depth.isDepthWriteEnabled = metal.write
        }
        stencil = device.makeDepthStencilState(descriptor: depth)!
    }
    public func setCullWindingStencil(_ renderCmd: MTLRenderCommandEncoder) {
        // flipped between .metal and .vision state
        if renderState != RenderDepth.state {
            renderState = RenderDepth.state
            makeStencil()
        }
        renderCmd.setDepthStencilState(stencil)

        switch renderState {
        case .immer:
            renderCmd.setCullMode(immer.cull)
            renderCmd.setFrontFacing(immer.winding)

        case .metal:
            renderCmd.setCullMode(metal.cull)
            renderCmd.setFrontFacing(metal.winding)
        }
    }
}
