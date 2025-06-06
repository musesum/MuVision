// created by musesum on 1/4/24

import MetalKit

public class CubeMesh: MeshMetal {

    var model: CubeModel!
    
    init(_ renderState: RenderState) {
        let immersed = RenderDepth(.none, .clockwise, .greater, true)
        let windowed = RenderDepth(.none, .clockwise, .less,    false)
        let depthRendering = DepthRendering(immersed, windowed, renderState)
        super.init(depthRendering)
        
        let nameFormats: [VertexNameFormat] = [
            ("position", .float4),
        ]
        let vertexStride = MemoryLayout<VertexCube>.stride

        model = CubeModel(nameFormats, vertexStride)
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        mtkMesh = try! MTKMesh(mesh: model.mdlMesh, device: device)
    }
}
