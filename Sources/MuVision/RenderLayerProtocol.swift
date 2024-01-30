// created by musesum.

#if os(visionOS)

import Metal
import CompositorServices

public protocol RenderLayerProtocol {

    func makeResources()

    func makePipeline()

    func updateUniforms(_ drawable: LayerRenderer.Drawable)


    func computeLayer(_ commandBuf: MTLCommandBuffer)

    func renderLayer(_ commandBuf: MTLCommandBuffer,
                     _ layerDrawable: LayerRenderer.Drawable)
}

#endif
