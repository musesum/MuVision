// created by musesum on 1/4/24

import MetalKit

public class CubeMesh: MeshMetal {

    var model: CubeModel!
    
    init() {

        super.init(DepthRendering(
            immer: RenderDepth(.none, .clockwise, .greater, true),
            metal: RenderDepth(.none, .clockwise, .less,    false)))

        let nameFormats: [VertexNameFormat] = [
            ("position", .float4),
        ]
        let vertexStride = MemoryLayout<VertexCube>.stride

        model = CubeModel(nameFormats, vertexStride)
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        mtkMesh = try! MTKMesh(mesh: model.mdlMesh, device: device)
    }
}
