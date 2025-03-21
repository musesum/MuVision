// created by musesum on 12/25/23

import MetalKit
import Spatial
import MuFlo
public typealias VertexNameFormat = (String, MTLVertexFormat)

open class MeshModel<Item> {

    public var vertexBuf: MTLBuffer!
    public var indexBuf: MTLBuffer!
    public var vertices: [Item]!
    public var indices: [UInt32]!

    public var modelVD = MDLVertexDescriptor()
    public var mdlMesh: MDLMesh!

    public init (_ nameFormats: [VertexNameFormat],
                 _ vertexStride: Int) {

        makeModelVD(nameFormats,vertexStride)
    }
    
    public func makeModelVD(_ nameFormats: [ (String, MTLVertexFormat)],
                            _ layoutStride: Int) {
        var offset = 0
        for (index,(name,format)) in nameFormats.enumerated() {
            addModelVD(index, name, format, &offset)
        }

        modelVD.layouts[0] = MDLVertexBufferLayout(stride: layoutStride)

        func addModelVD(_ index: Int,
                        _ name: String,
                        _ format: MTLVertexFormat,
                        _ offset: inout Int) {
            let stride: Int
            switch format {
            case .float : stride = MemoryLayout<Float>.size
            case .float2: stride = MemoryLayout<Float>.size * 2
            case .float3: stride = MemoryLayout<Float>.size * 3
            case .float4: stride = MemoryLayout<Float>.size * 4
            default: return err("unknown format \(format)")
            }
            let convert: [MTLVertexFormat: MDLVertexFormat] = [
                .float :.float, 
                .float2:.float2,
                .float3:.float3,
                .float4:.float4,
            ]
            guard let modelFormat = convert[format] else { return err("modelFormat")}

            modelVD.attributes[index] = MDLVertexAttribute(
                name: name,
                format: modelFormat,
                offset: offset,
                bufferIndex: 0)

            offset += stride

            func err(_ msg: String) {
                PrintLog("⁉️ MeshModel:: addModelVD err: \(msg)")
            }
        }
    }

    public func updateBuffers(_ verticesLen : Int,
                              _ indicesLen  : Int) {

        guard let device = MTLCreateSystemDefaultDevice() else { return }

        vertices.withUnsafeBytes { bufferPointer in

            let vertexData = Data(bufferPointer) // untested for warning fix
            let allocator = MTKMeshBufferAllocator(device: device)
            let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
            let indexData = Data(bytes: indices, count: indicesLen)
            let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

            let submesh = MDLSubmesh(indexBuffer  : indexBuffer,
                                     indexCount   : indices.count,
                                     indexType    : .uint32,
                                     geometryType : .triangles,
                                     material     : nil)

            mdlMesh = MDLMesh(vertexBuffers : [vertexBuffer],
                              vertexCount   : vertices.count,
                              descriptor    : modelVD,
                              submeshes     : [submesh])
        }
    }
}
