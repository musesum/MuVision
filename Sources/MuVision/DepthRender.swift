// created by musesum on 1/9/24

import MetalKit

/// visionOS will changes stencil and cull requirements
public enum MetalVisionState: String {
    case metal
    case vision
    public var script: String { return rawValue }

}

public class DepthRender {

    public static var state: MetalVisionState = .metal

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

public class DepthRenderState {

    var device   : MTLDevice
    var vision   : DepthRender
    var metal    : DepthRender
    var stateNow : MetalVisionState
    var stencil  : MTLDepthStencilState!

    public init(_ device: MTLDevice,
                vision : DepthRender,
                metal  : DepthRender) {

        self.device = device
        self.vision = vision
        self.metal  = metal
        self.stateNow = DepthRender.state
        makeStencil()
    }
    public init(_ device: MTLDevice,
                vision: DepthRender) {

        DepthRender.state = .vision

        self.device = device
        self.vision = vision
        self.metal  = vision
        self.stateNow  = .vision
        makeStencil()
    }
    func makeStencil() {

        let depth = MTLDepthStencilDescriptor()

        switch stateNow {

        case .vision:
            depth.depthCompareFunction = vision.compare
            depth.isDepthWriteEnabled = vision.write

        case .metal:
            depth.depthCompareFunction = metal.compare
            depth.isDepthWriteEnabled = metal.write
        }
        stencil = device.makeDepthStencilState(descriptor: depth)!
    }
    public func setCullWindingStencil(_ renderCmd: MTLRenderCommandEncoder) {
        // flipped between .metal and .vision state
        if stateNow != DepthRender.state {
            stateNow = DepthRender.state
            makeStencil()
        }
        renderCmd.setDepthStencilState(stencil)

        switch stateNow {
        case .vision:
            renderCmd.setCullMode(vision.cull)
            renderCmd.setFrontFacing(vision.winding)

        case .metal:
            renderCmd.setCullMode(metal.cull)
            renderCmd.setFrontFacing(metal.winding)
        }
    }
}
