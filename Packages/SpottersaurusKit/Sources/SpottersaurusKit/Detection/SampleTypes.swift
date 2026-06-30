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
