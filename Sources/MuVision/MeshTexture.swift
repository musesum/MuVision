//  Created by musesum on 8/4/23.

import MetalKit
import Spatial

open class MeshTexture: MeshMetal {

    private var texName: String!
    public var texture: MTLTexture!

    public init(_ device  : MTLDevice,
                _ texName : String,
                cull: MTLCullMode,
                winding: MTLWinding) throws {

        super.init(device, cull: cull, winding: winding)
        self.texName = texName
        self.texture = device.load(texName)
    }

    override open func drawMesh(_ renderCmd: MTLRenderCommandEncoder) {
        
        renderCmd.setFragmentTexture(texture, index: TextureIndex.colori)
        super.drawMesh(renderCmd)
    }
}

