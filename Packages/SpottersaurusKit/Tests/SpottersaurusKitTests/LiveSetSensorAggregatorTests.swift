//
//  LiveSetSensorAggregatorTests.swift
//  SpottersaurusKitTests
//
//  Headless tests for the sensor-buffer/telemetry bookkeeping the Watch's
//  `LiveSetViewModel` used to carry inline (docs/PLAN.md Phase 2 task 10 —
//  the "God-ViewModel" finding). Everything here runs on synthetic
//  `DeviceMotionSample` buffers with injected time: no CoreMotion, no
//  HealthKit, no wall-clock.
//

import XCTest
import Foundation
@testable import SpottersaurusKit

final class LiveSetSensorAggregatorTests: XCTestCase {

    // MARK: - Synthetic device-motion fixtures
    //
    // Same shape as `ReplayTests.DeviceMotionBuilder`: `userAccelerationG`
    // carries only the gravity-removed signal and `gravityG` is the constant
    // CoreMotion-convention down vector, so
    // `GravityRemover.axialAcceleration(deviceMotion:)` lands on the
    // up-positive axial convention the engine expects. Kept file-local so test
    // files stay independent.

    private struct DeviceMotionBuilder {
        let dt = 0.02
        let g = standardGravityMS2
        var samples: [DeviceMotionSample] = []
        var t = 0.0

        private mutating func append(uaZ: Double) {
            samples.append(DeviceMotionSample(
                timestamp: t,
                userAccelerationG: Vector3(x: 0, y: 0, z: uaZ),
                gravityG: Vector3(x: 0, y: 0, z: -1.0),
                rotationRateRadS: .zero,
                attitude: .identity
            ))
            t += dt
        }

        /// A racked / paused stretch: no linear acceleration.
        mutating func still(_ duration: Double) {
            var local = 0.0
            while local < duration {
                append(uaZ: 0)
                local += dt
            }
        }

        /// A velocity bump v(τ) = A·sin²(π τ/T) — acceleration is a full sine
        /// period, so the bar starts and ends at rest. A>0 concentric (up),
        /// A<0 eccentric (down).
        mutating func bump(amplitude A: Double, duration T: Double) {
            var local = 0.0
            while local < T {
                let a = A * (Double.pi / T) * sin(2 * Double.pi * local / T)
                append(uaZ: a / g)
                local += dt
            }
        }

        /// An isometric grind: jittery acceleration integrating to ~no
        /// velocity — the bar is stuck mid-rep.
        mutating func grindPlateau(_ duration: Double, amplitude: Double = 0.8, freq: Double = 5) {
            var local = 0.0
            while local < duration {
                let a = amplitude * sin(2 * Double.pi * freq * local)
                append(uaZ: a / g)
                local += dt
            }
        }
    }

    /// `n` clean reps: still, eccentric down, concentric up, still.
    private func cleanDeviceMotion(reps n: Int, amplitude A: Double = 0.5, concentric T: Double = 0.8) -> [DeviceMotionSample] {
        var b = DeviceMotionBuilder()
        b.still(0.4)
        for _ in 0..<n {
            b.bump(amplitude: -A, duration: T)
            b.bump(amplitude: A, duration: T)
            b.still(0.4)
        }
        return b.samples
    }

    /// One slow-but-completed grind rep: Stage-1 territory against a brisk
    /// baseline, unremarkable against a sluggish one.
    private func grindDeviceMotion() -> [DeviceMotionSample] {
        var b = DeviceMotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.5, duration: 0.8)
        b.bump(amplitude: 0.28, duration: 1.5)
        b.still(0.4)
        return b.samples
    }

    /// One pinned rep: rises partway, then the bar stalls with no lockout —
    /// Stage-2 ("RACK IT") territory.
    private func pinDeviceMotion() -> [DeviceMotionSample] {
        var b = DeviceMotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.5, duration: 0.8)
        b.bump(amplitude: 0.45, duration: 0.6)
        b.grindPlateau(1.8)
        b.still(0.4)
        return b.samples
    }

    /// A long quiet stretch at the fixture's 50 Hz — enough elapsed time to
    /// push the rolling windows past their limits without any rep structure.
    private func stillMotion(seconds: Double) -> [DeviceMotionSample] {
        var b = DeviceMotionBuilder()
        b.still(seconds)
        return b.samples
    }

    private func benchCalibration() -> CalibrationValues {
        Calibration().calibrate(lift: .bench, warmupDeviceMotion: cleanDeviceMotion(reps: 3))
    }

    /// A bench aggregator already calibrated off three clean warmup reps —
    /// the state a lifter is in when the work set starts.
    private func makeAggregator() -> LiveSetSensorAggregator {
        LiveSetSensorAggregator(lift: .bench, calibration: benchCalibration())
    }

    /// Splits a buffer into the small batches `CMBatchedSensorManager`
    /// actually delivers, so the tests exercise the "engine re-analyses the
    /// whole rolling buffer on every batch" path rather than a single shot.
    private func batches(of samples: [DeviceMotionSample], size: Int = 40) -> [[DeviceMotionSample]] {
        stride(from: 0, to: samples.count, by: size).map {
            Array(samples[$0..<min($0 + size, samples.count)])
        }
    }

    // MARK: - Rep emission

    /// The core of the extraction: the engine re-lists every rep still inside
    /// the rolling buffer on every batch, so the aggregator must hand each
    /// completed rep to its caller exactly once.
    func test_workingSetMotionEmitsEachRepExactlyOnce_acrossReplayedBuffers() {
        var aggregator = makeAggregator()
        var reps: [RepResult] = []

        for batch in batches(of: cleanDeviceMotion(reps: 3)) {
            reps += aggregator.ingestMotion(batch, routing: .workingSet, at: 0).newReps
        }

        XCTAssertEqual(reps.map(\.repIndex), [0, 1, 2])
    }

    // MARK: - Spot-event gating

    /// The P1-1c "stuck RACK IT" guarantee, now owned here: a pinned rep stays
    /// inside the rolling buffer for many batches, so its `.rackIt` is
    /// re-listed by the engine every tick. The caller must only ever see it
    /// once, or resolving the alert would re-latch it on the next batch.
    func test_pinnedRepEmitsItsRackItOnlyOnce_thoughTheEngineReplaysItEveryBatch() {
        var aggregator = makeAggregator()
        var events: [SpotEvent] = []

        for batch in batches(of: pinDeviceMotion()) {
            events += aggregator.ingestMotion(batch, routing: .workingSet, at: 0).newEvents
        }

        let rackIts = events.filter { $0.kind == .rackIt }
        XCTAssertEqual(rackIts.count, 1, "a single pin must escalate exactly once")
        XCTAssertEqual(Set(events.map { "\($0.kind)-\($0.repIndex)" }).count, events.count, "no (kind, repIndex) may repeat")
    }

    // MARK: - Arming a new set

    /// Arming must wipe the previous set's history: its reps must not keep the
    /// rep counter climbing, and its events must not silence the new set's
    /// identical rep-0 escalation.
    func test_armClearsThePreviousSetsHistory_repsCountFromZeroAndRepZeroCanReAlert() {
        var aggregator = makeAggregator()
        for batch in batches(of: pinDeviceMotion()) {
            _ = aggregator.ingestMotion(batch, routing: .workingSet, at: 0)
        }

        aggregator.arm()

        var reps: [RepResult] = []
        var events: [SpotEvent] = []
        for batch in batches(of: pinDeviceMotion()) {
            let result = aggregator.ingestMotion(batch, routing: .workingSet, at: 0)
            reps += result.newReps
            events += result.newEvents
        }

        XCTAssertEqual(reps.map(\.repIndex).first, 0, "the new set's first rep is rep 0, not a continuation")
        XCTAssertEqual(events.filter { $0.kind == .rackIt && $0.repIndex == 0 }.count, 1, "the new set's rep 0 must be able to escalate again")
    }

    // MARK: - Warmup calibration

    /// Warmup reps are baseline material, not working-set reps: they refine a
    /// candidate `CalibrationValues` and stay out of the detection buffer, so
    /// the work set that follows still starts at rep 0.
    func test_warmupMotionRefinesACandidateBaselineWithoutFeedingTheDetectionBuffer() {
        var aggregator = LiveSetSensorAggregator(lift: .bench, calibration: .fallback(for: .bench))
        var candidate: CalibrationValues?
        var warmupReps: [RepResult] = []

        for batch in batches(of: cleanDeviceMotion(reps: 3)) {
            let result = aggregator.ingestMotion(batch, routing: .warmupCalibration, at: 0)
            candidate = result.calibrationCandidate
            warmupReps += result.newReps
        }

        XCTAssertEqual(candidate?.repCount, 3, "three clean warmup reps must be seen as three")
        XCTAssertTrue(warmupReps.isEmpty, "warmup motion must not be reported as completed work-set reps")

        let workingSet = batches(of: cleanDeviceMotion(reps: 1)).map {
            aggregator.ingestMotion($0, routing: .workingSet, at: 0)
        }
        XCTAssertEqual(workingSet.flatMap(\.newReps).map(\.repIndex), [0], "the work set starts at rep 0, unpolluted by warmup samples")
    }

    /// Starting a fresh warmup capture must discard the previous attempt's
    /// reps rather than averaging the two together.
    func test_beginningWarmupCalibrationDiscardsThePreviousWarmupBuffer() {
        var aggregator = LiveSetSensorAggregator(lift: .bench, calibration: .fallback(for: .bench))
        for batch in batches(of: cleanDeviceMotion(reps: 3)) {
            _ = aggregator.ingestMotion(batch, routing: .warmupCalibration, at: 0)
        }

        aggregator.beginWarmupCalibration()

        var candidate: CalibrationValues?
        for batch in batches(of: cleanDeviceMotion(reps: 1)) {
            candidate = aggregator.ingestMotion(batch, routing: .warmupCalibration, at: 0).calibrationCandidate
        }
        XCTAssertEqual(candidate?.repCount, 1, "the new warmup capture sees only its own rep")
    }

    /// Saving the warmup baseline must change what the engine judges working
    /// reps against: the same slow rep is a grind against a brisk baseline and
    /// unremarkable against a sluggish one.
    func test_applyingASavedBaselineChangesWhatCountsAsAGrind() {
        let sluggish = CalibrationValues(
            lift: .bench,
            baselineConcentricSeconds: 4.0,
            velocityBandLowerMS: 0.01,
            velocityBandUpperMS: 5.0,
            repCount: 3
        )

        func grindEvents(from aggregator: inout LiveSetSensorAggregator) -> [SpotEvent] {
            batches(of: grindDeviceMotion()).flatMap {
                aggregator.ingestMotion($0, routing: .workingSet, at: 0).newEvents
            }
        }

        var uncalibrated = LiveSetSensorAggregator(lift: .bench, calibration: sluggish)
        XCTAssertTrue(grindEvents(from: &uncalibrated).isEmpty, "sanity: nothing is slow next to a 4s baseline")

        var calibrated = LiveSetSensorAggregator(lift: .bench, calibration: sluggish)
        calibrated.applyCalibration(benchCalibration())
        XCTAssertTrue(
            grindEvents(from: &calibrated).contains { $0.kind == .grinding },
            "the applied warmup baseline must be what the working set is judged against"
        )
    }

    /// Arming clears the previous set's *detection* state, not the baseline —
    /// warmup happens before the work set, so the set that follows must still
    /// be judged against it.
    func test_armingKeepsTheAppliedBaseline() {
        var aggregator = LiveSetSensorAggregator(lift: .bench, calibration: .fallback(for: .bench))
        aggregator.applyCalibration(benchCalibration())

        aggregator.arm()

        let events = batches(of: grindDeviceMotion()).flatMap {
            aggregator.ingestMotion($0, routing: .workingSet, at: 0).newEvents
        }
        XCTAssertTrue(events.contains { $0.kind == .grinding }, "the armed set is still judged against the warmup baseline")
    }

    // MARK: - Pipeline telemetry

    /// Samples that arrive while the set isn't accepting reps (racked,
    /// resting, complete) still prove the sensor is alive, so they count
    /// toward telemetry even though they're dropped from detection.
    func test_batchesArrivingWhileTheSetIsNotListeningStillProveTheSensorIsAlive() {
        var aggregator = makeAggregator()
        let batch = Array(cleanDeviceMotion(reps: 1).prefix(50))

        let result = aggregator.ingestMotion(batch, routing: .telemetryOnly, at: 1_000)
        let telemetry = aggregator.telemetry(sensorRunning: true, now: 1_000.5)

        XCTAssertTrue(result.newReps.isEmpty, "dropped batches produce no reps")
        XCTAssertTrue(result.newEvents.isEmpty, "dropped batches produce no events")
        XCTAssertEqual(telemetry.samplesPerSecond, 50, "all 50 samples arrived inside the trailing 1s window")
        XCTAssertEqual(telemetry.lastSampleAge ?? .nan, 0.5, accuracy: 1e-9)
        XCTAssertTrue(telemetry.sensorRunning, "the caller's sensor-running flag passes through")
    }

    /// Before anything arrives there is nothing to report — the readout must
    /// say "no samples yet" rather than "0s ago".
    func test_telemetryReportsNoSampleAgeBeforeAnythingHasArrived() {
        let aggregator = makeAggregator()
        let telemetry = aggregator.telemetry(sensorRunning: false, now: 1_000)

        XCTAssertNil(telemetry.lastSampleAge)
        XCTAssertEqual(telemetry.samplesPerSecond, 0)
        XCTAssertFalse(telemetry.hrFlowing)
    }

    /// HR arrives far less often than motion, so "flowing" is a recency
    /// question: a reading from a couple of seconds ago still counts, one from
    /// ten seconds ago does not.
    func test_heartRateIsReportedFlowingOnlyWhileReadingsAreRecent() {
        var aggregator = makeAggregator()
        aggregator.ingestHeartRate(HRSample(timestamp: 3, beatsPerMinute: 148), at: 1_000)

        XCTAssertTrue(aggregator.telemetry(sensorRunning: true, now: 1_002).hrFlowing)
        XCTAssertFalse(aggregator.telemetry(sensorRunning: true, now: 1_010).hrFlowing, "a stale HR reading must not read as flowing")
    }

    // MARK: - Rolling windows (bounded memory)

    /// A long set must not grow the detection buffer without bound: it keeps a
    /// rolling 30s of motion, which is several reps of context for the engine
    /// and a fixed memory ceiling for the Watch.
    func test_theMotionBufferKeepsARollingThirtySecondsOfSamples() {
        var aggregator = makeAggregator()
        for batch in batches(of: stillMotion(seconds: 60)) {
            _ = aggregator.ingestMotion(batch, routing: .workingSet, at: 0)
        }

        XCTAssertEqual(Double(aggregator.bufferedMotionSampleCount), 30 * 50, accuracy: 2, "30s at the fixture's 50 Hz")
    }

    /// The warmup buffer gets a longer window than the working set — a
    /// calibration wants several unhurried reps — but is still bounded, so a
    /// lifter who leaves warmup capture running doesn't grow it forever.
    func test_theWarmupBufferKeepsARollingFortyFiveSecondsOfSamples() {
        var aggregator = LiveSetSensorAggregator(lift: .bench, calibration: .fallback(for: .bench))
        for batch in batches(of: stillMotion(seconds: 90)) {
            _ = aggregator.ingestMotion(batch, routing: .warmupCalibration, at: 0)
        }

        XCTAssertEqual(Double(aggregator.bufferedMotionSampleCount), 45 * 50, accuracy: 2, "45s at the fixture's 50 Hz")
    }

    /// HR gets the longest window of the three: the engine compares working
    /// reps against a pre-set baseline heart rate, which has to survive the
    /// whole set.
    func test_theHeartRateBufferKeepsARollingSixtySecondsOfReadings() {
        var aggregator = makeAggregator()
        for second in 0...120 {
            aggregator.ingestHeartRate(HRSample(timestamp: Double(second), beatsPerMinute: 150), at: 1_000)
        }

        XCTAssertEqual(Double(aggregator.bufferedHeartRateSampleCount), 61, accuracy: 1, "60s of once-a-second readings")
    }
}
