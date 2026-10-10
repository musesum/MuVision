//  created by musesum on 2/28/23.

import Foundation
import CoreMotion
import UIKit
import RealityKit

import simd

actor MotionActor {
    private var sceneOrientation: matrix_float4x4 = matrix_identity_float4x4

    func setOrientation(_ mat: matrix_float4x4) {
        sceneOrientation = mat
    }
    func getOrientation() -> matrix_float4x4 {
        sceneOrientation
    }
}


@MainActor
public class Motion {

    public static var shared = Motion()
    var motion: CMMotionManager?
    private let orientationActor = MotionActor() // ← new actor
    /// the low-pass on the attitude, before the screen's own turn is added
    public var turnFilter = TurnFilter()

    public init() {
        motion = CMMotionManager()
        updateMotion()
    }

    func updateMotion() {
        if let motion, motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1 / 60.0
            motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
        }
    }

    public func updateDeviceOrientation() async -> matrix_float4x4 {
        var mat = matrix_identity_float4x4
        if  let motion, motion.isDeviceMotionAvailable,
            let deviceMotion = motion.deviceMotion {

            let a = deviceMotion.attitude.rotationMatrix

            // the attitude's columns cycled, a rotation still
            let X = SIMD3<Float>(Float(a.m12), Float(a.m22), Float(a.m32))
            let Y = SIMD3<Float>(Float(a.m13), Float(a.m23), Float(a.m33))
            let Z = SIMD3<Float>(Float(a.m11), Float(a.m21), Float(a.m31))
            let attitude = simd_quatf(simd_float3x3(X, Y, Z))
            // the low-pass takes the magnetometer's wobble off the heading;
            // the gyro's speed opens its cutoff so a real turn is not lagged
            let rate = deviceMotion.rotationRate
            let speed = Float((rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot())
            let turn = turnFilter.filter(attitude, speed: speed, at: deviceMotion.timestamp)
            mat = matrix_float4x4(turn)
#if os(visionOS)
            let radians = Float.pi/2
#else
            let radians = UIDevice.current.orientation.rotatation()
#endif
            let axis = SIMD3<Float>(x: 0, y: 0, z: 1)
            let simdRotation = matrix_float4x4(simd_quatf(angle: radians, axis: axis))
            mat = simdRotation * mat
        }
        // store orientation in actor
        await orientationActor.setOrientation(mat)
        // return latest value
        return await orientationActor.getOrientation()
    }

    public func currentOrientation() async -> matrix_float4x4 {
        await orientationActor.getOrientation()
    }
}

nonisolated(unsafe) var LastDeviceOrientation = UIDeviceOrientation.unknown

extension UIDeviceOrientation {

    @MainActor
    func guessOrientation() -> UIDeviceOrientation {

        if LastDeviceOrientation != .unknown {
            return LastDeviceOrientation
        }

        switch self {

        case .unknown, .faceUp, .faceDown:

            let idiom = UIDevice.current.userInterfaceIdiom
            return idiom == .phone ? .portrait : .landscapeLeft

        default:

            return self
        }
    }
    @MainActor
    private func transform(_ a: CMAttitude) -> Transform {

        switch self {

        case .unknown, .faceUp, .faceDown:

            return transform(for: guessOrientation())

        default:

            LastDeviceOrientation = self
            return transform(for: self)
        }

        func transform(for orientation: UIDeviceOrientation) -> Transform {

            switch orientation {
            case .landscapeLeft      : return rpy( a.pitch, -a.roll,  a.yaw)
            case .portrait           : return rpy( a.roll,   a.pitch, a.yaw)
            case .portraitUpsideDown : return rpy(-a.roll,  -a.pitch, a.yaw)
            case .landscapeRight     : return rpy(-a.pitch,  a.roll,  a.yaw)
            default                  : return rpy( a.roll,  -a.pitch, a.yaw)
            }
            func rpy(_ roll: Double,
                     _ pitch: Double,
                     _ yaw: Double) -> Transform {

                return Transform(pitch : Float(pitch),
                                  yaw  : Float(yaw),
                                  roll : Float(roll))
            }
        }
    }
    @MainActor
    func rotatation() -> Float {

        func rotation(for orientation: UIDeviceOrientation) -> Float {

            switch orientation {
            case .portrait           : return   0
            case .landscapeLeft      : return  .pi/2
            case .landscapeRight     : return -.pi/2
            case .portraitUpsideDown : return  .pi
            default                  : return   0
            }
        }
        switch self {
        case .unknown, .faceUp, .faceDown :

            return rotation(for: guessOrientation())

        default:

            LastDeviceOrientation = self
            return rotation(for: self)
        }
    }
}
