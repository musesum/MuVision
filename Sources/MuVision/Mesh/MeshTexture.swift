//  Created by musesum on 8/4/23.

import MetalKit
import Spatial

open class MeshTexture: MeshMetal {

    private var texName: String!
    public var texture: MTLTexture!

    override open func drawMesh(_ renderEnc: MTLRenderCommandEncoder,
                                _ renderState: RenderState) {

        renderEnc.setFragmentTexture(texture, index: TextureIndex.colori)
        super.drawMesh(renderEnc, renderState)
    }
}
