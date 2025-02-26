import MetalKit

struct FlatVertex {
    var position: vector_float2
    var texCoord: vector_float2  // 2D texture coordinate

    init (_ px: Float, _ py: Float, _ tx: Float, _ ty: Float)  {
        position = simd_make_float2(px, py)
        texCoord = simd_make_float2(tx, ty)
    }
}

