// created by musesum on 12/22/23

import simd

extension SIMD4 {
    public var xyz: SIMD3<Scalar> {
        SIMD3(x, y, z)
    }
}

extension SIMD3<Float> {
    func hash(_ max: Float) -> Scalar {
        let h = ((x+max) * max * max) + ((y+max) * max) + (z + max)
        return h
    }
    var script: String {
        "(\(x.digits(0...2)), \(y.digits(0...2)), \(z.digits(0...2)))"
    }
}
extension SIMD4<Float> {
    func hash(_ max: Float) -> Scalar {
        let h = ((x+max) * max * max) + ((y+max) * max) + (z + max)
        return h
    }
    var script: String {
        "(\(x.digits(0...2)), \(y.digits(0...2)), \(z.digits(0...2)), \(w.digits(0...2)))"
    }
}
extension SIMD4<Double> {
    
    public var script: String {
        "(\(x.digits(0...2)), \(y.digits(0...2)), \(z.digits(0...2)), \(w.digits(0...2)))"
    }
}
extension simd_float4x4 {

    var script: String {
        return "(\(columns.0.script), \(columns.1.script), \(columns.2.script), \(columns.3.script))"
    }
}
extension simd_double4x4 {

    var script: String {
        return "[\(columns.0.script), \(columns.1.script), \(columns.2.script), \(columns.3.script)]"
    }
}
