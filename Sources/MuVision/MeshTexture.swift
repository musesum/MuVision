//  Created by musesum on 8/4/23.

import MetalKit
import Spatial

open class MeshTexture: MeshMetal {

    private var texName: String!
    public var texture: MTLTexture!

    public init(_ device  : MTLDevice,
                _ texName : String,
                _ renderDepth: RenderDepth) throws {

        super.init(DepthRendering(device, immerse: renderDepth))
        self.texName = texName
        self.texture = device.load(texName)
    }

    override open func drawMesh(_ renderCmd: MTLRenderCommandEncoder) {
        
        renderCmd.setFragmentTexture(texture, index: TextureIndex.colori)
        super.drawMesh(renderCmd)
    }
}

