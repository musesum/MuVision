// created by musesum on 12/22/23

import UIKit
import Metal
import CoreImage
import simd
import ModelIO
import MetalKit

open class MeshModel {

    let device: MTLDevice
    let metalVD: MTLVertexDescriptor
    
    public  var vertexBuf: MTLBuffer! //??? private
    public  var indexBuf: MTLBuffer! //??? private

    public var vertices: [Float]!
    public var indices: [UInt16]!
    public var mdlMesh: MDLMesh!

    public init(_ device: MTLDevice,
                _ metalVD: MTLVertexDescriptor) {

        self.device = device
        self.metalVD = metalVD
    }

    public func updateBuffers(verticesLen : Int,
                              indicesLen  : Int) {

        vertexBuf = device.makeBuffer(bytes: vertices, length: verticesLen)
        indexBuf  = device.makeBuffer(bytes: indices , length: indicesLen )

        let allocator = MTKMeshBufferAllocator(device: device)
        let vertexData = Data(bytes: vertices, count: verticesLen)
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.stride)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let submesh = MDLSubmesh(indexBuffer  : indexBuffer,
                                 indexCount   : indices.count,
                                 indexType    : .uint16,
                                 geometryType : .triangles,
                                 material     : nil)

        mdlMesh = MDLMesh(vertexBuffers : [vertexBuffer],
                          vertexCount   : vertices.count,
                          descriptor    : metalVD.modelVD,
                          submeshes     : [submesh])
    }
}
