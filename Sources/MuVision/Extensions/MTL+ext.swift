// created by musesum on 11/19/24
import MuFlo
import Metal

#if os(visionOS)
public let MuRenderPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
#else
public let MuRenderPixelFormat = MTLPixelFormat.bgra8Unorm
#endif
public let MuComputePixelFormat = MTLPixelFormat.bgra8Unorm
public let MuHeightPixelFormat = MTLPixelFormat.r16Unorm

