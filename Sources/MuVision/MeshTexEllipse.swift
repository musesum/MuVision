//  Created by musesum on 8/4/23.

import MetalKit
import Spatial
import simd


/// not used direct
struct VertexMesh {
    let position : SIMD3<Float>
    let texCoord : SIMD2<Float>
    let normal   : SIMD3<Float>
}


open class MeshTexEllipse: MeshTexture {
    
    var radius = CGFloat(1)
    var inward = false
    
    public init(_ device: MTLDevice,
                texName : String,
                compare : MTLCompareFunction,
                radius  : CGFloat,
                inward  : Bool,
                winding : MTLWinding) throws {
        
        try super.init(device  : device,
                       texName : texName,
                       compare : compare,
                       winding : winding)
        
        self.radius = radius
        self.inward = inward
        
        guard let modelMesh = modelEllipsoid(device) else {
            throw RendererError.badVertex
        }
        mtkMesh = try MTKMesh(mesh: modelMesh, device: device)
    }
    
    func modelEllipsoid(_ device: MTLDevice) -> MDLMesh? {
        let allocator = MTKMeshBufferAllocator(device: device)
        let radii = SIMD3<Float>(repeating: Float(radius))
        let modelMesh = MDLMesh.newEllipsoid(
            withRadii        : radii,
            radialSegments   : 24,
            verticalSegments : 24,
            geometryType     : .triangles,
            inwardNormals    : inward,
            hemisphere       : false,
            allocator        : allocator)

        let nameFormats: [VertexNameFormat] = [
            (MDLVertexAttributePosition         , .float3),
            (MDLVertexAttributeTextureCoordinate, .float2),
            (MDLVertexAttributeNormal           , .float3)
             ]
        let layoutStride = MemoryLayout<VertexMesh>.stride
        makeMetalVD(nameFormats, layoutStride)

        let modelVD = makeModelFromMetalVD(nameFormats, layoutStride)
        modelMesh.vertexDescriptor = modelVD

        return modelMesh
    }
}
