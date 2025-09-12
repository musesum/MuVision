// created by musesum on 1/4/24
import Metal

public class CubeModel: MeshModel<Float> {

    override public init(_ nameFormats: [VertexNameFormat],
                         _ vertexStride: Int) {

        super.init(nameFormats, vertexStride)

        let r = Float(10)
        vertices = [ // each 4 elements is 1 VertexCube element
        /* +Y */  -r,+r,+r,1, +r,+r,+r,1, +r,+r,-r,1, -r,+r,-r,1,
        /* -Y */  -r,-r,-r,1, +r,-r,-r,1, +r,-r,+r,1, -r,-r,+r,1,
        /* +Z */  -r,-r,+r,1, +r,-r,+r,1, +r,+r,+r,1, -r,+r,+r,1,
        /* -Z */  +r,-r,-r,1, -r,-r,-r,1, -r,+r,-r,1, +r,+r,-r,1,
        /* -X */  -r,-r,-r,1, -r,-r,+r,1, -r,+r,+r,1, -r,+r,-r,1,
        /* +X */  +r,-r,+r,1, +r,-r,-r,1, +r,+r,-r,1, +r,+r,+r,1,
        ]
        indices =  [
            0,   2,  3,   2,  0,  1,
            4,   6,  7,   6,  4,  5,
            8,  10, 11,  10,  8,  9,
            12, 14, 15,  14, 12, 13,
            16, 18, 19,  18, 16, 17,
            20, 22, 23,  22, 20, 21,
        ]

        let verticesLen = vertices.count / 4 * MemoryLayout<VertexCube>.stride
        let indicesLen = indices.count * MemoryLayout<UInt32>.stride

        guard let device = MTLCreateSystemDefaultDevice() else { return  }
        vertexBuf = device.makeBuffer(bytes: vertices, length: verticesLen)
        indexBuf  = device.makeBuffer(bytes: indices,  length: indicesLen )
        vertexBuf.label = "CubeVertex"
        indexBuf.label = "CubeIndex"

        updateBuffers(verticesLen,indicesLen)
    }
}
