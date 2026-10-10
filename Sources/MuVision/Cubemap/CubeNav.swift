//  created by musesum on 9/19/26.

import Foundation
import QuartzCore
import simd
import MuFlo

/// the six faces plato.cube's buttons turn to, in the order its leaf
/// lays them out. The viewer's R is the index cube's `left` quad and L its
/// `right`: both hold the same mirrored picture
public enum CubeFace: Int, CaseIterable, Sendable {
    case front, right, back, left, up, down

    public var letter: String { ["F", "R", "B", "L", "U", "D"][rawValue] }
    public var name: String { ["front", "right", "back", "left", "up", "down"][rawValue] }

    /// the user turn that looks at this face straight on: a yaw to the four
    /// sides, a pitch to U and D. U shows its B edge on top, D its F edge
    public var turn: simd_quatf {
        switch self {
        case .front : return simd_quatf(angle: 0,        axis: [0, 1, 0])
        case .right : return simd_quatf(angle: .pi / 2,  axis: [0, 1, 0])
        case .back  : return simd_quatf(angle: .pi,      axis: [0, 1, 0])
        case .left  : return simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        case .up    : return simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        case .down  : return simd_quatf(angle: .pi / 2,  axis: [1, 0, 0])
        }
    }
    /// the face in model space, as seen from inside looking at it straight
    /// on: its outward normal, and the screen's right and up across it.
    /// `turn` carries these to (0,0,-1), (1,0,0) and (0,1,0)
    public var normal: SIMD3<Float> {
        switch self {
        case .front : return [ 0,  0, -1]
        case .right : return [ 1,  0,  0]
        case .back  : return [ 0,  0,  1]
        case .left  : return [-1,  0,  0]
        case .up    : return [ 0,  1,  0]
        case .down  : return [ 0, -1,  0]
        }
    }
    public var right: SIMD3<Float> {
        switch self {
        case .front : return [ 1, 0,  0]
        case .right : return [ 0, 0,  1]
        case .back  : return [-1, 0,  0]
        case .left  : return [ 0, 0, -1]
        case .up    : return [ 1, 0,  0]
        case .down  : return [ 1, 0,  0]
        }
    }
    public var up: SIMD3<Float> {
        switch self {
        case .up    : return [0, 0,  1]
        case .down  : return [0, 0, -1]
        default     : return [0, 1,  0]
        }
    }
}

/// the view the cube and plato share: the device's own turn, re-zeroed on
/// a face button and on off, times the user's turn that plato.cube's
/// yaw and pitch spin and its F R B L U D buttons ease to.
///
///     view = device · device0⁻¹ · user
///
/// device0 starts at the identity, so until a face button or an off the view
/// follows the device's heading as it always has. yaw turns the view right
/// about the model's vertical, pitch tilts it up about the screen's horizontal,
/// however the device is held;
/// 1 is a whole turn in 32 seconds. A face button eases over four times
/// sky.main.anim's seconds, 3t²−2t³ as MuFlo's EaseInOut; on over the
/// anim's own, in step with the cube's fade in. Off holds the view through
/// the fade out, the flat screen coming in over the anim's seconds, and only
/// then eases to F over the anim's seconds again, so no turn shows through
/// the crossfade. Off stops the spin, yaw and pitch to 0, until on again; zoom and
/// frustum stay.
/// Every renderer calls view(_:now:) each
/// frame; the time it measures makes a second caller in the same frame a no-op
public final class CubeNav: @unchecked Sendable {

    public static let shared = CubeNav()

    /// radians a second at speed 1: a whole turn in 32 seconds
    public static let radiansPerSecond = Float.pi / 16
    /// a face button's ease against sky.main.anim's seconds: 2 s → 8 s
    public static let faceSlow = 4.0
    /// the longest frame step a spin integrates, so a stall does not jump
    static let maxStep = 0.1

    struct Ease {
        let from: simd_quatf
        let to: simd_quatf
        /// off's starts after the fade out; until then the turn holds at from
        let start: Double
        let duration: Double
        /// off's and on's ease to F runs its course; a speed takes over after
        let hold: Bool
    }

    private let lock = NSLock()
    private var user    = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var device  = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // the last one a renderer passed
    private var device0 = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // the device at the last re-zero
    private var ease: Ease?
    private var lastTime: Double?
    private var isOn = true
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var zoomNow: Float = 0
    private var duration: Double = 2

    private weak var cubemap˚: Flo?
    private weak var nav˚: Flo?
    private weak var anim˚: Flo?

    public init() {}

    // MARK: - flo

    /// plato.cubemap x is on/off, plato.cube yaw pitch zoom the yaw and pitch speeds
    /// and zoom, sky.main.anim x the ease's seconds. Binds once per root
    public func bind(_ root˚: Flo) {
        let cubemap˚ = root˚.findPath("plato.cubemap")
        let nav˚     = root˚.findPath("plato.cube")
        let anim˚ = root˚.findPath("sky.main.anim")
        lock.lock()
        let bound = cubemap˚ != nil && cubemap˚ === self.cubemap˚
        if !bound {
            self.cubemap˚ = cubemap˚
            self.nav˚  = nav˚
            self.anim˚ = anim˚
        }
        lock.unlock()
        if bound { return }

        cubemap˚?.addClosure { [weak self] f, _ in self?.setOn(f.boolVal("x")) }
        nav˚? .addClosure { [weak self] f, _ in self?.setNav(f) }
        anim˚?.addClosure { [weak self] f, _ in self?.setDuration(f) }

        // an archive may have set these before the bind: start from them
        lock.lock()
        isOn = cubemap˚?.boolVal("x") ?? true
        lock.unlock()
        if let nav˚ { setNav(nav˚) }
        if let anim˚ { setDuration(anim˚) }
    }

    private func tween(_ flo: Flo, _ name: String) -> Float? {
        (flo.exprs?.nameAny[name] as? Scalar).map { Float($0.tween) }
    }
    private func setNav(_ nav˚: Flo) {
        let x = tween(nav˚, "yaw"), y = tween(nav˚, "pitch"), z = tween(nav˚, "zoom")
        lock.lock()
        if let x { yaw = x }
        if let y { pitch = y }
        if let z { zoomNow = z }
        lock.unlock()
    }
    private func setDuration(_ anim˚: Flo) {
        guard let x = anim˚.val("x") else { return }
        lock.lock()
        duration = max(0, x)
        lock.unlock()
    }

    /// cube → square stops the spin, yaw and pitch back to 0, and holds the view
    /// through the cube's fade out, sky.main.anim's seconds; only once the
    /// flat screen is fully in does the view ease to F, over the anim's
    /// seconds again, so no turn shows through the crossfade. Zoom and
    /// frustum stay, as plato, still drawn, shows them. Square → cube
    /// starts the cube from its defaults: yaw, pitch, zoom and frustum back to their script
    /// values, zoom and frustum easing there, and the view eases to F from
    /// wherever the device has taken it meanwhile, in step with the fade
    /// in, so the cube fades in on F and plato does not jump. Either ease
    /// runs its course before a speed set meanwhile takes over
    func setOn(_ on: Bool, now: Double = CACurrentMediaTime()) {
        lock.lock()
        let wasOn = isOn
        isOn = on
        if wasOn != on {
            easeLocked(to: CubeFace.front.turn, now, hold: true, after: on ? 0 : duration)
        }
        lock.unlock()
        if wasOn, !on { centreNav(Visitor(0, .model), ["yaw", "pitch"]) }
        if !wasOn, on { centreNav(Visitor(0, .model)) }
    }

    /// nav's `names` back to their script values, fired so the frustum edge
    /// and the leaf follow
    public func centreNav(_ visit: Visitor, _ names: [String] = ["yaw", "pitch", "zoom", "frustum"]) {
        lock.lock()
        let nav˚ = self.nav˚
        lock.unlock()
        guard let nav˚ else { return }
        Self.centre(nav˚, visit, names)
    }
    public static func centre(_ nav˚: Flo, _ visit: Visitor, _ names: [String] = ["yaw", "pitch", "zoom", "frustum"]) {
        guard let exprs = nav˚.exprs else { return }
        let origins: [(String, Double)] = names.compactMap { name in
            (exprs.nameAny[name] as? Scalar).map { (name, $0.origin) }
        }
        nav˚.setNameNums(origins, .fire, visit)
    }

    // MARK: - turn

    /// a face button: fold the device's turn since the last re-zero into the
    /// user turn, so nothing jumps, then ease from there to the face over
    /// four times sky.main.anim's seconds, 3t²−2t³, the short way round
    public func face(_ face: CubeFace, now: Double = CACurrentMediaTime()) {
        lock.lock()
        easeLocked(to: face.turn, now, slow: Self.faceSlow)
        lock.unlock()
    }
    /// `after` seconds delay the ease's start, the turn held meanwhile
    private func easeLocked(to: simd_quatf, _ now: Double,
                            slow: Double = 1, hold: Bool = false, after: Double = 0) {
        let now = max(now, lastTime ?? now)
        advanceLocked(now)
        user = simd_normalize(device * device0.inverse * user)
        device0 = device
        if duration > 0 {
            ease = Ease(from: user, to: to, start: now + after, duration: duration * slow, hold: hold)
        } else {
            user = to
            ease = nil
        }
    }

    /// the renderer's frame: the device turn in, the view out, advanced to `now`
    public func view(_ device: matrix_float4x4,
                     now: Double = CACurrentMediaTime()) -> matrix_float4x4 {
        let r = simd_float3x3(device.columns.0.xyz, device.columns.1.xyz, device.columns.2.xyz)
        lock.lock()
        self.device = simd_normalize(simd_quatf(r))
        advanceLocked(now)
        let rest = device0.inverse * user
        lock.unlock()
        return device * matrix_float4x4(rest)
    }

    /// the view's turn as the last frame left it, not advanced: the leaf's cube
    public var viewTurn: simd_quatf {
        lock.lock(); defer { lock.unlock() }
        return simd_normalize(device * device0.inverse * user)
    }
    /// the user's turn alone
    public var userTurn: simd_quatf {
        lock.lock(); defer { lock.unlock() }
        return user
    }
    public var on: Bool {
        lock.lock(); defer { lock.unlock() }
        return isOn
    }
    public var easing: Bool {
        lock.lock(); defer { lock.unlock() }
        return ease != nil
    }
    /// nav zoom, 0…1, as it eases: EyeBuf narrows the field of view by it
    public var zoom: Float {
        lock.lock(); defer { lock.unlock() }
        return zoomNow
    }
    /// yaw and pitch speeds, -1…1
    public var speeds: SIMD2<Float> {
        lock.lock(); defer { lock.unlock() }
        return [yaw, pitch]
    }

    public func advance(to now: Double) {
        lock.lock()
        advanceLocked(now)
        lock.unlock()
    }
    /// an ease runs to its end unless a speed takes over; a spin integrates
    /// the time since the last frame, and only while on
    private func advanceLocked(_ now: Double) {
        // the cube's and plato's frames read the clock before the lock, in
        // either order: never step back
        let now = max(now, lastTime ?? now)
        let dt = Float(min(Self.maxStep, now - (lastTime ?? now)))
        lastTime = now
        if let ease, (yaw == 0 && pitch == 0) || !isOn || ease.hold {
            let t = ease.duration > 0 ? (now - ease.start) / ease.duration : 1
            if t >= 1 {
                user = ease.to
                self.ease = nil
            } else {
                // before its start, off's fade out, the turn holds at from
                let s = Float(max(0, t))
                user = simd_slerp(ease.from, ease.to, s * s * (3 - 2 * s))
            }
            return
        }
        ease = nil
        guard isOn, dt > 0, yaw != 0 || pitch != 0 else { return }
        let turn = yaw * Self.radiansPerSecond * dt
        let tilt = pitch * Self.radiansPerSecond * dt
        // yaw about the model's vertical, on the right; pitch about the
        // screen's horizontal, on the left of the whole view, so carried
        // back through the device's turn since the last re-zero
        let pitchQ = simd_quatf(angle: -tilt, axis: [1, 0, 0])
        let yawQ = simd_quatf(angle: turn, axis: [0, 1, 0])
        let m = device * device0.inverse
        user = simd_normalize(m.inverse * pitchQ * m * user * yawQ)
    }

    /// back to launch: tests, and a pipeline built again
    public func reset() {
        lock.lock()
        user = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        device = user
        device0 = user
        ease = nil
        lastTime = nil
        isOn = true
        yaw = 0
        pitch = 0
        zoomNow = 0
        duration = 2
        cubemap˚ = nil
        nav˚ = nil
        anim˚ = nil
        lock.unlock()
    }
}
