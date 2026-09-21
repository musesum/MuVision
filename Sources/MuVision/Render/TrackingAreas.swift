// created by musesum on 8/24/26

// gaze tracking areas: a second color attachment the compositor reads for hover and taps
// nothing below changes until a layer configures a format

import Metal
#if os(visionOS)
import CompositorServices
#endif

public enum TrackingAreas {

    /// the format the immersive layer carries; nil leaves the render pass and every
    /// pipeline descriptor as they were
    nonisolated(unsafe) public private(set) static var format: MTLPixelFormat?

    /// how many areas one frame may register: the format's own ceiling on render values
    nonisolated(unsafe) public private(set) static var maxValue: UInt32 = 0

    /// whether the pass being encoded carries the areas attachment: the render loop
    /// sets it per drawable, a capture drawable without the textures leaves it false
    nonisolated(unsafe) public internal(set) static var passAreas = false

#if os(visionOS)
    /// app opt-in from `makeConfiguration`: a supported format, r8Uint first
    @available(visionOS 26.0, *)
    @discardableResult
    public static func configure(_ capabilities: LayerRenderer.Capabilities,
                                 _ configuration: inout LayerRenderer.Configuration) -> Bool {

        let supported = capabilities.supportedTrackingAreasFormats
        // r16Uint first: r8Uint's 254-value pool exhausts on dense boards
        let picked: MTLPixelFormat? = supported.contains(.r16Uint) ? .r16Uint
            : supported.contains(.r8Uint) ? .r8Uint : supported.first
        guard let picked else { return false }
        configuration.trackingAreasFormat = picked
        format = picked
        // r8Uint carries 255, the floor to fall back on when the layer answers nothing
        let properties = try? LayerRenderer.Properties(configuration: configuration)
        maxValue = UInt32(properties?.trackingAreasMaxValue.rawValue ?? 255)
        return true
    }
#endif
}
