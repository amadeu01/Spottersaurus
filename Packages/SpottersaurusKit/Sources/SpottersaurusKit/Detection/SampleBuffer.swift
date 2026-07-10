//
//  SampleBuffer.swift
//  SpottersaurusKit
//
//  Windowing helpers over timestamped sample streams plus the gravity-removal
//  front end of the detection pipeline. All pure value types / static math:
//  no CoreMotion, no HealthKit, no wall-clock — everything is driven off the
//  sample timestamps so the engine is deterministic and unit-testable on macOS.
//

import Foundation

/// Standard gravity, m/s². CoreMotion accelerometer values arrive in g, so the
/// pipeline multiplies by this to work in SI units (matching velocity in m/s).
public let standardGravityMS2: Double = 9.80665

/// Anything carried on the detection timeline. `timestamp` is seconds on a
/// monotonic clock relative to set-arm (never wall-clock).
public protocol Timestamped {
    var timestamp: TimeInterval { get }
}

extension MotionSample: Timestamped {}
extension HRSample: Timestamped {}
extension DeviceMotionSample: Timestamped {}

/// A single bar-axis (vertical) linear-acceleration reading, gravity removed,
/// in m/s². Positive points along the lift's concentric direction (up).
public struct LinearSample: Codable, Sendable, Equatable, Timestamped {
    /// Seconds since the set was armed (monotonic).
    public var timestamp: TimeInterval
    /// Gravity-removed acceleration projected onto the bar axis, m/s² (up +).
    public var axialMS2: Double

    public init(timestamp: TimeInterval, axialMS2: Double) {
        self.timestamp = timestamp
        self.axialMS2 = axialMS2
    }
}

/// A thin, ordered window over a timestamped sample stream. Keeps the samples
/// sorted by timestamp and exposes the slicing the segmenter / integrator need.
public struct SampleBuffer<Element: Timestamped & Sendable>: Sendable {
    public private(set) var samples: [Element]

    /// Builds a buffer, sorting by timestamp so downstream math can assume order.
    public init(_ samples: [Element]) {
        self.samples = samples.sorted { $0.timestamp < $1.timestamp }
    }

    public var isEmpty: Bool { samples.isEmpty }
    public var count: Int { samples.count }

    /// Wall span of the buffer in seconds (last − first), 0 when empty.
    public var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.timestamp - first.timestamp
    }

    /// Mean spacing between consecutive samples, 0 when fewer than two samples.
    public var meanSampleInterval: TimeInterval {
        guard samples.count > 1 else { return 0 }
        return duration / Double(samples.count - 1)
    }

    /// Samples whose timestamp falls in the inclusive `[from, to]` window.
    public func window(from: TimeInterval, to: TimeInterval) -> [Element] {
        samples.filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    /// The trailing `seconds` of samples ending at `end` (defaults to the last
    /// sample's timestamp). Useful for rolling live-window checks on the Watch.
    public func trailing(_ seconds: TimeInterval, endingAt end: TimeInterval? = nil) -> [Element] {
        guard let last = end ?? samples.last?.timestamp else { return [] }
        return window(from: last - seconds, to: last)
    }
}

/// Removes gravity from a raw accelerometer stream and projects the residual
/// linear acceleration onto the bar (vertical) axis.
///
/// Gravity is the low-frequency component of the signal, so it is tracked with
/// an exponential moving average (time constant `timeConstant`). The lift's own
/// acceleration over a concentric is ~zero-mean (the bar starts and ends a rep
/// near rest), so the EMA settles on gravity while the rep signal passes
/// through. The bar axis is taken as the current gravity direction; the linear
/// residual is projected onto it and converted to m/s².
public enum GravityRemover {

    /// Projects `motion` onto the gravity (bar) axis with gravity removed.
    /// - Parameter timeConstant: EMA time constant in seconds for the gravity
    ///   estimate. Larger = slower adaptation (less rep-signal attenuation).
    public static func axialAcceleration(
        _ motion: [MotionSample],
        timeConstant: Double = 2.0
    ) -> [LinearSample] {
        guard let first = motion.first else { return [] }

        // Seed the gravity estimate with the first sample so there is no
        // start-up transient (the first residual is exactly zero).
        var gX = first.accelX
        var gY = first.accelY
        var gZ = first.accelZ
        var prevT = first.timestamp

        var out: [LinearSample] = []
        out.reserveCapacity(motion.count)

        for (i, s) in motion.enumerated() {
            let dt = i == 0 ? 0 : max(s.timestamp - prevT, 0)
            let alpha = dt <= 0 ? 0 : dt / (timeConstant + dt)
            gX += alpha * (s.accelX - gX)
            gY += alpha * (s.accelY - gY)
            gZ += alpha * (s.accelZ - gZ)

            let lX = s.accelX - gX
            let lY = s.accelY - gY
            let lZ = s.accelZ - gZ

            let gMag = (gX * gX + gY * gY + gZ * gZ).squareRoot()
            // Component of the linear residual along the gravity unit vector.
            let axialG = gMag > 1e-6 ? (lX * gX + lY * gY + lZ * gZ) / gMag : lZ

            out.append(LinearSample(timestamp: s.timestamp, axialMS2: axialG * standardGravityMS2))
            prevT = s.timestamp
        }
        return out
    }

    /// Projects fused device-motion `userAcceleration` onto the CoreMotion-
    /// supplied `gravity` vector to recover bar-axis linear acceleration —
    /// the ADR 0007 fused front end.
    ///
    /// Unlike `axialAcceleration(_:timeConstant:)`, gravity here comes
    /// straight from CoreMotion's sensor fusion (accelerometer + gyroscope)
    /// per sample, so there is no EMA to settle and no rep-signal attenuation
    /// from an estimate lagging behind a genuinely inclined bar path.
    ///
    /// Sign: CoreMotion's `gravity` vector points in the direction gravity
    /// pulls — toward the ground, e.g. ~(0, 0, -1) for a device lying
    /// screen-up flat — which is the *opposite* sense from the raw front
    /// end's EMA estimate (which tracks the raw accelerometer's at-rest
    /// reading and therefore points up, ~(0, 0, +1) in the same pose). The
    /// bar's "up"/concentric direction is `-gravity` (normalized), so this
    /// negates the projection onto the gravity vector to land on the same
    /// up-positive convention `LinearSample.axialMS2` documents and the raw
    /// front end already produces.
    public static func axialAcceleration(deviceMotion: [DeviceMotionSample]) -> [LinearSample] {
        deviceMotion.map { sample in
            let gHat = sample.gravityG.normalized
            let axialG = -sample.userAccelerationG.dot(gHat)
            return LinearSample(timestamp: sample.timestamp, axialMS2: axialG * standardGravityMS2)
        }
    }
}
