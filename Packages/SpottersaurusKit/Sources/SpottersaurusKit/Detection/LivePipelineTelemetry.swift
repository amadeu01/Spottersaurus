//
//  LivePipelineTelemetry.swift
//  SpottersaurusKit
//
//  Pure, hardware-free snapshot of "is the live sensor pipeline actually
//  running" — surfaced on the Watch so the lifter/dev can tell the
//  auto-detection is live rather than a mocked demo. `make` derives the
//  snapshot from plain timestamp arrays so it's unit-testable without
//  CoreMotion/HealthKit; the Watch feeds it recent wall-clock ingest
//  timestamps.
//

import Foundation

/// A point-in-time readout of the live motion/HR sensor pipeline's health.
public struct LivePipelineTelemetry: Sendable, Equatable {
    /// Whether the motion sensor stream (`WatchMotionStreamAdapter` /
    /// `CMBatchedSensorManager`) is currently started.
    public var sensorRunning: Bool
    /// Whether a heart-rate sample has arrived within the recent HR window.
    public var hrFlowing: Bool
    /// Motion samples received per second, measured over the trailing
    /// `window` before `now`.
    public var samplesPerSecond: Double
    /// Seconds since the newest motion sample arrived, or `nil` if no
    /// motion sample has arrived at all.
    public var lastSampleAge: TimeInterval?

    public init(
        sensorRunning: Bool,
        hrFlowing: Bool,
        samplesPerSecond: Double,
        lastSampleAge: TimeInterval?
    ) {
        self.sensorRunning = sensorRunning
        self.hrFlowing = hrFlowing
        self.samplesPerSecond = samplesPerSecond
        self.lastSampleAge = lastSampleAge
    }

    /// Everything off — sensor not started, nothing ever received.
    public static let idle = LivePipelineTelemetry(
        sensorRunning: false,
        hrFlowing: false,
        samplesPerSecond: 0,
        lastSampleAge: nil
    )

    /// Derives a telemetry snapshot from recent sample-arrival timestamps.
    ///
    /// - Parameters:
    ///   - motionSampleTimestamps: Timestamps (any consistent clock domain —
    ///     the Watch uses wall-clock ingest time) of recently received
    ///     motion samples. Callers only need to retain samples within a
    ///     small trailing buffer; older entries don't affect the result.
    ///   - hrSampleTimestamps: Timestamps of recently received HR samples,
    ///     same clock domain as `now`.
    ///   - now: The current instant, same clock domain as the timestamp
    ///     arrays above.
    ///   - sensorRunning: Whether the motion adapter reports itself started
    ///     (passed through untouched — this function doesn't infer it from
    ///     sample activity, since a started-but-momentarily-quiet sensor is
    ///     still "running").
    ///   - window: Trailing window (seconds) over which `samplesPerSecond`
    ///     is measured. Defaults to 1 second.
    ///   - hrWindow: Trailing window (seconds) within which an HR sample
    ///     must have arrived for `hrFlowing` to be true. Defaults to 5
    ///     seconds — HR updates arrive far less often than motion.
    public static func make(
        motionSampleTimestamps: [TimeInterval],
        hrSampleTimestamps: [TimeInterval],
        now: TimeInterval,
        sensorRunning: Bool,
        window: TimeInterval = 1.0,
        hrWindow: TimeInterval = 5.0
    ) -> LivePipelineTelemetry {
        let windowFloor = now - window
        let samplesInWindow = motionSampleTimestamps.filter { $0 > windowFloor && $0 <= now }.count
        let samplesPerSecond = window > 0 ? Double(samplesInWindow) / window : 0

        let lastMotionTimestamp = motionSampleTimestamps.max()
        let lastSampleAge = lastMotionTimestamp.map { now - $0 }

        let lastHRTimestamp = hrSampleTimestamps.max()
        let hrFlowing = lastHRTimestamp.map { now - $0 <= hrWindow } ?? false

        return LivePipelineTelemetry(
            sensorRunning: sensorRunning,
            hrFlowing: hrFlowing,
            samplesPerSecond: samplesPerSecond,
            lastSampleAge: lastSampleAge
        )
    }
}
