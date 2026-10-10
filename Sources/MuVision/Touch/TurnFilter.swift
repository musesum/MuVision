// created by musesum on 9/28/26

import simd

/// a low-pass on the device's turn. CoreMotion's attitude against magnetic
/// north wobbles a degree or so, several times a second, while the device
/// rests: the magnetometer correcting the heading. A fixed average that hid
/// the wobble would lag a real turn by as much, so the cutoff opens with the
/// gyro's speed (a one-euro filter): at rest the view settles, in motion it
/// keeps up. Each sample slerps the turn toward it by the fraction its
/// interval and the cutoff give, a first-order low-pass along the arc
public struct TurnFilter {

    /// Hz at rest, well under the wobble's few Hz
    public var minCutoff: Float
    /// Hz added for each radian a second the gyro reads
    public var beta: Float

    /// the filtered turn, nil before the first sample
    public private(set) var turn: simd_quatf?
    private var time: Double?

    public init(minCutoff: Float = 0.5, beta: Float = 6) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    /// the sample at `time` seconds, its `speed` the device's spin in
    /// radians a second. The first sample is taken as it is; the same time
    /// again (a second renderer in the same frame) returns the turn as it was
    public mutating func filter(_ sample: simd_quatf,
                                speed: Float,
                                at time: Double) -> simd_quatf {
        var q = simd_normalize(sample)
        guard let turn, let last = self.time else {
            self.turn = q
            self.time = time
            return q
        }
        guard time > last else { return turn }
        // q and -q are the same turn: keep to the side the last one is on
        if simd_dot(q.vector, turn.vector) < 0 { q = simd_quatf(vector: -q.vector) }
        let dt = Float(time - last)
        let cutoff = max(1e-3, minCutoff + beta * max(0, speed))
        let tau = 1 / (2 * .pi * cutoff)
        let a = 1 / (1 + tau / dt)
        let next = simd_normalize(simd_slerp(turn, q, a))
        self.turn = next
        self.time = time
        return next
    }

    public mutating func reset() {
        turn = nil
        time = nil
    }
}
