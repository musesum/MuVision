//  Created by musesum on 8/4/23.

import MetalKit
import Spatial

open class MeshTexture: MeshMetal {

    private var texName: String!
    public var texture: MTLTexture!

    override open func drawMesh(
        _ encoder: MTLRenderCommandEncoder,
        _ state: RenderState) {

        encoder.setFragmentTexture(texture, index: TextureIndex.colori)
        super.drawMesh(encoder, state)
    }
}
