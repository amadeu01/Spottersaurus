//
//  SampleTypes.swift
//  SpottersaurusKit
//
//  Platform-neutral sample structs that flow into the detection pipeline.
//  The Watch feeds these from CoreMotion (`CMBatchedSensorManager`) and
//  HealthKit (`HKLiveWorkoutBuilder`), but the types themselves carry no
//  device-framework dependency so the engine is unit-testable on macOS
//  against recorded / synthetic buffers.
//

import Foundation

/// A single tri-axial accelerometer reading, gravity included. Units are
/// g (multiples of standard gravity), matching CoreMotion's convention.
/// `timestamp` is seconds on a monotonic clock relative to set arm.
public struct MotionSample: Codable, Sendable, Equatable {
    /// Seconds since the set was armed (monotonic, not wall-clock).
    public var timestamp: TimeInterval
    /// Acceleration along device X, in g.
    public var accelX: Double
    /// Acceleration along device Y, in g.
    public var accelY: Double
    /// Acceleration along device Z, in g.
    public var accelZ: Double

    public init(timestamp: TimeInterval, accelX: Double, accelY: Double, accelZ: Double) {
        self.timestamp = timestamp
        self.accelX = accelX
        self.accelY = accelY
        self.accelZ = accelZ
    }

    /// Euclidean magnitude of the tri-axial vector, in g. ~1.0 at rest.
    public var magnitude: Double {
        (accelX * accelX + accelY * accelY + accelZ * accelZ).squareRoot()
    }
}

/// A plain 3-D vector, used for the CoreMotion-shaped fields on
/// `DeviceMotionSample` (acceleration, gravity, rotation rate). Pure math, no
/// CoreMotion dependency, so the detection pipeline stays macOS-testable.
public struct Vector3: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    /// Euclidean magnitude of the vector.
    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }

    /// Dot product with `other`.
    public func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    /// Unit vector in the same direction, or `.zero` if this vector is ~0.
    public var normalized: Vector3 {
        let m = magnitude
        guard m > 1e-9 else { return .zero }
        return Vector3(x: x / m, y: y / m, z: z / m)
    }
}

/// A unit quaternion (w, x, y, z) describing device attitude relative to
/// CoreMotion's reference frame. Pure/Codable mirror of `CMQuaternion` — not
/// consumed by the detection math yet (reserved for the rotation-gating work
/// in ADR 0007), but carried through so the sample type is a complete mirror
/// of `CMDeviceMotion`.
public struct Quaternion: Codable, Sendable, Equatable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = Quaternion(w: 1, x: 0, y: 0, z: 0)
}

/// A single fused device-motion sample, mirroring CoreMotion's `CMDeviceMotion`
/// (delivered on the Watch via `CMBatchedSensorManager.deviceMotionUpdates()`).
/// Gravity and rotation rate come from CoreMotion's sensor fusion (accelerometer
/// + gyroscope), so `userAccelerationG` is a better gravity-removed signal than
/// the raw-accelerometer EMA estimate `GravityRemover` falls back to. Pure/
/// Codable, no CoreMotion import — the engine stays unit-testable on macOS
/// against recorded/synthetic buffers. See ADR 0007.
public struct DeviceMotionSample: Codable, Sendable, Equatable {
    /// Seconds since the set was armed (monotonic, not wall-clock). Same
    /// convention as `MotionSample.timestamp`.
    public var timestamp: TimeInterval

    /// Gravity-removed linear acceleration, in g. CoreMotion fuses this from
    /// the accelerometer and gyroscope, so it does not need (and should not
    /// use) the EMA gravity estimate the raw-accelerometer path relies on.
    public var userAccelerationG: Vector3

    /// The gravity vector, in g, expressed in the device's reference frame.
    /// Points in the direction gravity pulls (toward the ground) — e.g.
    /// ~(0, 0, -1) for a device lying screen-up flat — matching CoreMotion's
    /// `CMDeviceMotion.gravity` convention.
    public var gravityG: Vector3

    /// Rotation rate about each device axis, rad/s.
    public var rotationRateRadS: Vector3

    /// Device attitude relative to CoreMotion's reference frame at
    /// motion-manager start.
    public var attitude: Quaternion

    public init(
        timestamp: TimeInterval,
        userAccelerationG: Vector3,
        gravityG: Vector3,
        rotationRateRadS: Vector3,
        attitude: Quaternion
    ) {
        self.timestamp = timestamp
        self.userAccelerationG = userAccelerationG
        self.gravityG = gravityG
        self.rotationRateRadS = rotationRateRadS
        self.attitude = attitude
    }
}

/// A heart-rate reading from the live workout builder.
public struct HRSample: Codable, Sendable, Equatable {
    /// Seconds since the set was armed (monotonic, not wall-clock).
    public var timestamp: TimeInterval
    /// Instantaneous heart rate in beats per minute.
    public var beatsPerMinute: Double

    public init(timestamp: TimeInterval, beatsPerMinute: Double) {
        self.timestamp = timestamp
        self.beatsPerMinute = beatsPerMinute
    }
}
