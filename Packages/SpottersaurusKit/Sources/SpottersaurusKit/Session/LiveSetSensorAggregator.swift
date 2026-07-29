//
//  LiveSetSensorAggregator.swift
//  SpottersaurusKit
//
//  The sensor half of a live set, split out of the Watch's `LiveSetViewModel`
//  (docs/PLAN.md Phase 2 task 10 — the "God-ViewModel" finding). The view
//  model used to own the rolling sample buffers, the `SpotEngine`, the event
//  gate and the telemetry timestamps alongside its display state, which meant
//  none of that could be exercised without standing up a view model on-device.
//
//  Everything here is bookkeeping over sample buffers: what has arrived, what
//  is still worth keeping, and — crucially — what is *new*. `SpotEngine`
//  re-analyses the whole rolling buffer on every batch, so it re-lists every
//  rep and every event still inside the window; this type turns that
//  repeated whole-set analysis into an edge-triggered stream the caller can
//  hand straight to `SetLifecycleController` (see `SpotEventGate`, and
//  docs/backlog.md P1-1c). What the caller then *does* with a new rep or a
//  `.rackIt` — count it, latch an alert, log it — stays with the caller.
//
//  Pure and platform-neutral in the same sense as `SetLifecycleController`:
//  no CoreMotion, no HealthKit, no SwiftUI, and no wall-clock reads — arrival
//  times are injected — so it is fully testable headless on macOS.
//

import Foundation

/// Owns the raw sensor bookkeeping for one working set: rolling motion/HR
/// buffers, the `SpotEngine` and its calibration, and the dedup that turns the
/// engine's whole-buffer analysis into a stream of *new* reps and events.
///
/// Not `Equatable` (unlike its siblings in this folder): its identity is a few
/// thousand buffered samples plus a `SpotEngine`, and comparing two of those
/// is neither cheap nor meaningful.
public struct LiveSetSensorAggregator: Sendable {

    /// Which buffer an incoming motion batch belongs to.
    public enum MotionRouting: Sendable, Equatable {
        /// Warmup calibration is collecting: feed the warmup buffer and
        /// re-derive the candidate baseline from it.
        case warmupCalibration
        /// The set is live: feed the detection buffer and run the engine.
        case workingSet
        /// Nothing is listening for reps (idle, racked, resting, complete):
        /// the batch is dropped from detection but still counted as proof the
        /// sensor is alive.
        case telemetryOnly
    }

    /// What one motion batch produced.
    public struct MotionIngestResult: Sendable, Equatable {
        /// Reps completed since the previous batch, oldest first.
        public var newReps: [RepResult]
        /// Spot events not previously emitted, oldest first.
        public var newEvents: [SpotEvent]
        /// The baseline derived from the warmup buffer so far — non-`nil` only
        /// for `.warmupCalibration` batches.
        public var calibrationCandidate: CalibrationValues?

        public init(
            newReps: [RepResult] = [],
            newEvents: [SpotEvent] = [],
            calibrationCandidate: CalibrationValues? = nil
        ) {
            self.newReps = newReps
            self.newEvents = newEvents
            self.calibrationCandidate = calibrationCandidate
        }
    }

    private let lift: LiftKind
    private let config: SpotConfig
    private var spotEngine: SpotEngine
    private var warmupMotionSamples: [DeviceMotionSample] = []
    private var motionSamples: [DeviceMotionSample] = []
    private var heartRateSamples: [HRSample] = []
    private var processedRepCount = 0
    private var spotEventGate = SpotEventGate()

    /// Wall-clock (not set-relative) batch-arrival times, kept only for the
    /// `LivePipelineTelemetry` readout. Decoupled from the sample buffers
    /// above — those carry a monotonic clock relative to set arm, but
    /// staleness has to be measured against real elapsed time. Trimmed to a
    /// short trailing window: bounded memory, not a session history.
    private var motionIngestTimestamps: [TimeInterval] = []
    private var hrIngestTimestamps: [TimeInterval] = []
    private let telemetryRetention: TimeInterval = 2

    /// Rolling detection window (s): several reps of context for the engine,
    /// with a fixed memory ceiling regardless of set length.
    private static let motionWindow: TimeInterval = 30
    /// Rolling warmup window (s) — longer than the detection window because a
    /// calibration wants several unhurried reps.
    private static let warmupWindow: TimeInterval = 45
    /// Rolling HR window (s) — longest of the three: the engine compares
    /// working reps against a pre-set baseline that must outlive the set.
    private static let heartRateWindow: TimeInterval = 60

    public init(lift: LiftKind, calibration: CalibrationValues, config: SpotConfig = .conservative) {
        self.lift = lift
        self.config = config
        self.spotEngine = SpotEngine(lift: lift, calibration: calibration, config: config)
    }

    /// Motion samples currently retained across both buffers — what the
    /// Watch's "Motion: N samples" readout shows, and the visible half of the
    /// bounded-memory contract: this plateaus on a long set, it does not grow
    /// with set duration.
    public var bufferedMotionSampleCount: Int {
        motionSamples.count + warmupMotionSamples.count
    }

    /// Heart-rate readings currently retained — the other half of the
    /// bounded-memory contract.
    public var bufferedHeartRateSampleCount: Int {
        heartRateSamples.count
    }

    /// Ingests one motion batch. Every batch counts toward telemetry — even a
    /// dropped one proves the sensor is alive — and `routing` decides which
    /// buffer, if any, it also feeds.
    ///
    /// - Parameters:
    ///   - samples: The batch, in the fused device-motion shape (ADR 0007).
    ///   - routing: Which buffer the batch belongs to. The caller owns this
    ///     decision: it is the one holding the set's lifecycle state.
    ///   - ingestedAt: Wall-clock arrival instant, seconds since the reference
    ///     date. Injected rather than read here so the type stays pure.
    /// - Returns: Only what is new since the last batch.
    @discardableResult
    public mutating func ingestMotion(
        _ samples: [DeviceMotionSample],
        routing: MotionRouting,
        at ingestedAt: TimeInterval
    ) -> MotionIngestResult {
        recordMotionIngest(count: samples.count, at: ingestedAt)

        switch routing {
        case .telemetryOnly:
            return MotionIngestResult()

        case .warmupCalibration:
            warmupMotionSamples.append(contentsOf: samples)
            trimWarmupBuffer()
            let candidate = Calibration(config: config).calibrate(lift: lift, warmupDeviceMotion: warmupMotionSamples)
            return MotionIngestResult(calibrationCandidate: candidate)

        case .workingSet:
            motionSamples.append(contentsOf: samples)
            trimMotionBuffer()
            let analysis = spotEngine.process(deviceMotion: motionSamples, hr: heartRateSamples)
            return MotionIngestResult(
                newReps: repsCompletedSinceLastBatch(in: analysis),
                newEvents: spotEventGate.admitNew(from: analysis.events)
            )
        }
    }

    /// The engine reports every rep it can still see in the rolling buffer, so
    /// "new" means "past the highest rep index already reported".
    private mutating func repsCompletedSinceLastBatch(in analysis: SpotAnalysis) -> [RepResult] {
        var newReps: [RepResult] = []
        for rep in analysis.reps where rep.repIndex >= processedRepCount {
            newReps.append(rep)
            processedRepCount = rep.repIndex + 1
        }
        return newReps
    }

    /// Ingests one heart-rate reading. HR never completes a rep on its own —
    /// it only feeds the engine's baseline/spike context and the telemetry
    /// readout — so there is nothing to return.
    ///
    /// - Parameters:
    ///   - sample: The reading, timestamped seconds since set arm.
    ///   - ingestedAt: Wall-clock arrival instant, seconds since the reference
    ///     date, in the same domain as `telemetry(sensorRunning:now:)`.
    public mutating func ingestHeartRate(_ sample: HRSample, at ingestedAt: TimeInterval) {
        heartRateSamples.append(sample)
        trimHeartRateBuffer()
        hrIngestTimestamps.append(ingestedAt)
        trimTelemetryTimestamps(before: ingestedAt - telemetryRetention)
    }

    /// Health of the live sensor pipeline, derived from recent batch-arrival
    /// times. `sensorRunning` is passed through from the caller (which owns
    /// the motion adapter); `now` shares the clock domain of the `ingestedAt`
    /// values handed to the ingest methods.
    public func telemetry(sensorRunning: Bool, now: TimeInterval) -> LivePipelineTelemetry {
        LivePipelineTelemetry.make(
            motionSampleTimestamps: motionIngestTimestamps,
            hrSampleTimestamps: hrIngestTimestamps,
            now: now,
            sensorRunning: sensorRunning
        )
    }

    /// Rebuilds the engine around a new baseline — typically the one just
    /// derived from warmup reps, so the working set is judged against this
    /// lifter's own tempo instead of the per-lift fallback.
    public mutating func applyCalibration(_ values: CalibrationValues) {
        spotEngine = SpotEngine(lift: lift, calibration: values, config: config)
    }

    /// Starts a fresh warmup capture, discarding any previous attempt's reps.
    public mutating func beginWarmupCalibration() {
        warmupMotionSamples = []
    }

    /// Clears the previous set's detection state so the newly armed set starts
    /// from rep 0 with an empty event gate.
    public mutating func arm() {
        motionSamples = []
        heartRateSamples = []
        processedRepCount = 0
        spotEventGate.reset()
    }

    /// Drops motion samples older than the rolling detection window, measured
    /// from the newest sample's own set-relative timestamp (not wall-clock, so
    /// a replayed buffer trims identically to a live one).
    private mutating func trimMotionBuffer() {
        let floor = (motionSamples.last?.timestamp ?? 0) - Self.motionWindow
        motionSamples.removeAll { $0.timestamp < floor }
    }

    private mutating func trimWarmupBuffer() {
        let floor = (warmupMotionSamples.last?.timestamp ?? 0) - Self.warmupWindow
        warmupMotionSamples.removeAll { $0.timestamp < floor }
    }

    private mutating func trimHeartRateBuffer() {
        let floor = (heartRateSamples.last?.timestamp ?? 0) - Self.heartRateWindow
        heartRateSamples.removeAll { $0.timestamp < floor }
    }

    private mutating func recordMotionIngest(count: Int, at ingestedAt: TimeInterval) {
        guard count > 0 else { return }
        motionIngestTimestamps.append(contentsOf: Array(repeating: ingestedAt, count: count))
        trimTelemetryTimestamps(before: ingestedAt - telemetryRetention)
    }

    private mutating func trimTelemetryTimestamps(before floor: TimeInterval) {
        motionIngestTimestamps.removeAll { $0 < floor }
        hrIngestTimestamps.removeAll { $0 < floor }
    }
}
