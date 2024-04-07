// created by musesum on 12/19/23

import MetalKit
import Spatial
import ModelIO


open class MeshMetal {

    private var depthRendering: DepthRendering
    public var metalVD = MTLVertexDescriptor()
    public var mtkMesh: MTKMesh?
    public var eyeBuf: UniformEyeBuf?
    public var uniformBuf : MTLBuffer!

    public init(_ depthRenderState: DepthRendering) {
        self.depthRendering = depthRenderState
    }

    public func makeMetalVD(_ nameFormats: [VertexNameFormat],
                            _ layoutStride: Int) {
        var offset = 0
        for (index,(_,format)) in nameFormats.enumerated() {
            addMetalVD(index, format, &offset)
        }
        metalVD.layouts[0].stride = layoutStride
        metalVD.layouts[0].stepRate = 1
        metalVD.layouts[0].stepFunction = .perVertex
    }
    public func addMetalVD(_ index: Int,
                           _ format: MTLVertexFormat,
                           _ offset: inout Int) {
        let stride: Int
        switch format {
        case .float : stride = MemoryLayout<Float>.size
        case .float2: stride = MemoryLayout<Float>.size * 2
        case .float3: stride = MemoryLayout<Float>.size * 3
        case .float4: stride = MemoryLayout<Float>.size * 4
        default: return err("\(#function) unknown format \(format)")
        }
        metalVD.attributes[index].bufferIndex = 0
        metalVD.attributes[index].format = format
        metalVD.attributes[index].offset = offset
        offset += stride

        func err(_ msg: String) {
            print("⁉️ error: \(msg)")
        }
    }
    public func makeModelFromMetalVD(_ nameFormats: [VertexNameFormat],
                                     _ layoutStride: Int) -> MDLVertexDescriptor {

        let modelVD = MTKModelIOVertexDescriptorFromMetal(metalVD)
        if let attributes = modelVD.attributes as? [MDLVertexAttribute] {

            for (index,(name,_)) in nameFormats.enumerated() {
                attributes[index].name = name
            }
        }
        modelVD.layouts[0] = MDLVertexBufferLayout(stride: layoutStride)
        return modelVD
    }

    open func drawMesh(_ renderCmd: MTLRenderCommandEncoder) {

        guard let mtkMesh else { return err("mesh") }

        depthRendering.setCullWindingStencil(renderCmd)

        for (index, layout) in mtkMesh.vertexDescriptor.layouts.enumerated() {
            if let layout = layout as? MDLVertexBufferLayout,
               layout.stride != 0 {
                let vb = mtkMesh.vertexBuffers[index]
                renderCmd.setVertexBuffer(vb.buffer, offset: vb.offset, index: index)
            }
        }

        for submesh in mtkMesh.submeshes {
            renderCmd.drawIndexedPrimitives(
                type              : submesh.primitiveType,
                indexCount        : submesh.indexCount,
                indexType         : submesh.indexType,
                indexBuffer       : submesh.indexBuffer.buffer,
                indexBufferOffset : submesh.indexBuffer.offset)
        }
        func err(_ msg: String) {
            print("⁉️ drawMesh error: \(msg)")
        }
    }
}
