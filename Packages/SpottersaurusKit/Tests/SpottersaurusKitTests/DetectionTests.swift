//
//  DetectionTests.swift
//  SpottersaurusKitTests
//
//  Headless, hardware-free tests for the Phase 3 detection engine. All fixtures
//  are generated in code: a rep is a velocity "bump" (a sin² velocity profile,
//  whose acceleration is a full sine period so velocity starts and ends at rest),
//  with still pauses between reps and an optional isometric "grind plateau" for a
//  pinned bar. No binary fixtures, no CoreMotion, no wall-clock.
//

import XCTest
import Foundation
@testable import SpottersaurusKit

final class DetectionTests: XCTestCase {

    // MARK: - Synthetic fixture builder

    /// Builds a raw accelerometer stream (gravity on +Z, lift accel on +Z) from
    /// composable phases. Velocity bumps integrate to a self-contained up/down
    /// excursion; still phases let the segmenter's ZUPT reset between reps.
    private struct MotionBuilder {
        let dt = 0.02
        let g = standardGravityMS2
        var samples: [MotionSample] = []
        var t = 0.0

        /// A racked / paused stretch: gravity only, no lift acceleration.
        mutating func still(_ duration: Double) {
            var local = 0.0
            while local < duration {
                samples.append(MotionSample(timestamp: t, accelX: 0, accelY: 0, accelZ: 1.0))
                t += dt; local += dt
            }
        }

        /// A velocity bump v(τ) = A·sin²(π τ/T): acceleration is the derivative,
        /// a full sine period that returns the bar to rest. A>0 is concentric
        /// (up), A<0 eccentric (down).
        mutating func bump(amplitude A: Double, duration T: Double) {
            var local = 0.0
            while local < T {
                let a = A * (Double.pi / T) * sin(2 * Double.pi * local / T)
                samples.append(MotionSample(timestamp: t, accelX: 0, accelY: 0, accelZ: 1.0 + a / g))
                t += dt; local += dt
            }
        }

        /// An isometric grind: small jittery acceleration (above the still
        /// threshold so it is not racked) that integrates to ~zero velocity — a
        /// bar stuck mid-rep.
        mutating func grindPlateau(_ duration: Double, amplitude: Double = 0.8, freq: Double = 5) {
            var local = 0.0
            while local < duration {
                let a = amplitude * sin(2 * Double.pi * freq * local)
                samples.append(MotionSample(timestamp: t, accelX: 0, accelY: 0, accelZ: 1.0 + a / g))
                t += dt; local += dt
            }
        }
    }

    /// `n` clean reps: still, eccentric down, concentric up, still.
    private func cleanSet(reps n: Int, amplitude A: Double = 0.5, concentric T: Double = 0.8) -> [MotionSample] {
        var b = MotionBuilder()
        b.still(0.4)
        for _ in 0..<n {
            b.bump(amplitude: -A, duration: T)   // eccentric (down)
            b.bump(amplitude: A, duration: T)    // concentric (up)
            b.still(0.4)
        }
        return b.samples
    }

    /// One slow-but-completed grind rep (Stage-1 territory, no pin).
    private func grindSet() -> [MotionSample] {
        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.5, duration: 0.8)   // eccentric
        b.bump(amplitude: 0.28, duration: 1.5)   // slow concentric, still completes
        b.still(0.4)
        return b.samples
    }

    /// One pinned rep: rises partway, then the bar stalls (no lockout).
    private func pinSet() -> [MotionSample] {
        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.5, duration: 0.8)   // eccentric
        b.bump(amplitude: 0.45, duration: 0.6)   // partial concentric
        b.grindPlateau(1.8)                      // stuck mid-rep, no lockout
        b.still(0.4)
        return b.samples
    }

    private func makeBenchCalibration() -> CalibrationValues {
        Calibration().calibrate(lift: .bench, warmupMotion: cleanSet(reps: 3))
    }

    // MARK: - Segmenter

    func testSegmenterCountsKnownReps() {
        let motion = cleanSet(reps: 5)
        let phases = RepSegmenter().segment(motion: motion)
        XCTAssertEqual(phases.count, 5, "expected exactly 5 concentrics from a 5-rep buffer")
        for phase in phases {
            XCTAssertGreaterThan(phase.concentricSeconds, 0)
        }
    }

    // MARK: - Segmenter: setup phase (ADR 0006)

    /// Squat/bench: a walkout wiggle before the lifter ever settles (a lone
    /// upward excursion, no preceding descent) must be discarded outright —
    /// not read as a bout at all — leaving exactly the real reps.
    func testSegmenterDiscardsPreSettleWalkoutForSquatBench() {
        var b = MotionBuilder()
        b.bump(amplitude: 0.35, duration: 0.5)   // walkout: bar jostled out of the rack
        b.still(0.4)                              // settle: braced, ready to lift
        for _ in 0..<4 {
            b.bump(amplitude: -0.5, duration: 0.8)   // eccentric
            b.bump(amplitude: 0.5, duration: 0.8)    // concentric
            b.still(0.4)
        }

        let phases = RepSegmenter().segment(motion: b.samples, lift: .bench)
        XCTAssertEqual(phases.count, 4, "the pre-settle walkout wiggle must not be counted as a rep; got \(phases.count)")
        XCTAssertNotNil(phases.first?.eccentricStart, "rep 1 must be the real eccentric→concentric rep, not the walkout")
    }

    /// A lone upward excursion that slips past the settle heuristic (e.g. a
    /// re-rack adjustment right after an early pause) is still not rep 1: the
    /// rep-1 gate drops it because it has no preceding eccentric.
    func testSegmenterRepOneGateRejectsPostSettleReRackAdjustment() {
        var b = MotionBuilder()
        b.still(0.4)                               // settle achieved immediately
        b.bump(amplitude: 0.35, duration: 0.5)      // re-rack adjustment: lone upward bump
        b.still(0.4)                                // brief pause
        for _ in 0..<3 {
            b.bump(amplitude: -0.5, duration: 0.8)
            b.bump(amplitude: 0.5, duration: 0.8)
            b.still(0.4)
        }

        let phases = RepSegmenter().segment(motion: b.samples, lift: .bench)
        XCTAssertEqual(phases.count, 3, "a lone upward excursion with no preceding descent must not count as rep 1; got \(phases.count)")
        XCTAssertNotNil(phases.first?.eccentricStart)
    }

    /// Deadlift: the bar starts on the floor, so rep 1 is a genuine
    /// concentric-from-rest with no preceding eccentric — the approach/grip
    /// wiggle before the settle is discarded exactly as for squat/bench.
    func testSegmenterCountsDeadliftRepOneWithNoEccentric() {
        var b = MotionBuilder()
        b.bump(amplitude: 0.3, duration: 0.4)    // approach: setting grip, not yet settled
        b.still(0.4)                              // settle: grip set, ready to pull
        for _ in 0..<4 {
            b.bump(amplitude: 0.5, duration: 0.8)  // concentric: pull from the floor
            b.still(0.4)                            // dead-stop pause at the floor
        }

        let phases = RepSegmenter().segment(motion: b.samples, lift: .deadlift)
        XCTAssertEqual(phases.count, 4, "approach wiggle must be discarded, all 4 pulls counted; got \(phases.count)")
        XCTAssertNil(phases.first?.eccentricStart, "deadlift rep 1 is a concentric-from-rest with no preceding eccentric")
    }

    /// The rep-1 gate is genuinely per-lift: the same buffer (concentric-from-
    /// rest, then a normal eccentric→concentric rep) is read differently by
    /// deadlift vs bench.
    func testSegmenterRepOneGateDiffersByLift() {
        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: 0.5, duration: 0.8)     // concentric-from-rest, no preceding eccentric
        b.still(0.4)
        b.bump(amplitude: -0.5, duration: 0.8)    // eccentric
        b.bump(amplitude: 0.5, duration: 0.8)     // concentric
        b.still(0.4)

        let deadliftPhases = RepSegmenter().segment(motion: b.samples, lift: .deadlift)
        XCTAssertEqual(deadliftPhases.count, 2, "deadlift accepts the concentric-from-rest excursion as rep 1")

        let benchPhases = RepSegmenter().segment(motion: b.samples, lift: .bench)
        XCTAssertEqual(benchPhases.count, 1, "bench must reject the lone upward excursion as rep 1, keeping only the real eccentric→concentric rep")
    }

    // MARK: - Velocity integrator

    func testVelocityIntegratorRecoversKnownProfile() {
        // A pure concentric bump with peak velocity A and mean A/2.
        let A = 0.6, T = 1.0, dt = 0.02
        var linear: [LinearSample] = []
        var local = 0.0
        while local < T {
            let a = A * (Double.pi / T) * sin(2 * Double.pi * local / T)
            linear.append(LinearSample(timestamp: local, axialMS2: a))
            local += dt
        }

        let cv = VelocityIntegrator().integrate(linear)
        XCTAssertEqual(cv.peakMS, A, accuracy: 0.04, "peak velocity should recover A")
        XCTAssertEqual(cv.meanMS, A / 2, accuracy: 0.04, "mean velocity should recover A/2")
        XCTAssertGreaterThan(cv.displacementM, 0)
    }

    // MARK: - Calibration

    func testCalibrationProducesUsableBands() {
        let calib = makeBenchCalibration()
        XCTAssertEqual(calib.repCount, 3)
        XCTAssertGreaterThan(calib.baselineConcentricSeconds, 0.5)
        XCTAssertLessThan(calib.baselineConcentricSeconds, 1.5)
        XCTAssertGreaterThan(calib.velocityBandUpperMS, calib.velocityBandLowerMS)
        XCTAssertGreaterThan(calib.velocityBandLowerMS, 0)
    }

    func testSquatCalibrationDisablesVelocityBand() {
        let calib = Calibration().calibrate(lift: .squat, warmupMotion: cleanSet(reps: 3))
        XCTAssertEqual(calib.velocityBandLowerMS, 0)
        XCTAssertEqual(calib.velocityBandUpperMS, 0)
        XCTAssertGreaterThan(calib.baselineConcentricSeconds, 0)
    }

    // MARK: - Engine: false-alarm guard

    func testCleanRepsFireNoEvents() {
        let engine = SpotEngine(lift: .bench, calibration: makeBenchCalibration())
        let analysis = engine.process(motion: cleanSet(reps: 3))
        XCTAssertTrue(analysis.usedVelocityPath)
        XCTAssertEqual(analysis.reps.count, 3)
        XCTAssertTrue(analysis.events.isEmpty, "clean reps must not fire any event; got \(analysis.events)")
        XCTAssertFalse(analysis.reps.contains { $0.flaggedStall })
    }

    // MARK: - Engine: Stage 1 (grind)

    func testGrindFiresStageOneOnly() {
        let engine = SpotEngine(lift: .bench, calibration: makeBenchCalibration())
        let analysis = engine.process(motion: grindSet())

        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding }, "a slow grind must fire Stage 1")
        XCTAssertFalse(analysis.events.contains { $0.kind == .rackIt }, "a completed grind must not escalate to RACK IT")
        XCTAssertTrue(analysis.events.contains { $0.kind == .resolved }, "a completed grind should resolve")
        XCTAssertTrue(analysis.reps.contains { $0.flaggedStall && !$0.reachedRackIt })
    }

    // MARK: - Engine: Stage 2 (hard pin)

    func testHardPinFiresStageTwo() {
        let engine = SpotEngine(lift: .bench, calibration: makeBenchCalibration())
        let analysis = engine.process(motion: pinSet())

        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding }, "a pin starts as a grind")
        XCTAssertTrue(analysis.events.contains { $0.kind == .rackIt }, "a hard pin must escalate to RACK IT")

        let grind = analysis.events.first { $0.kind == .grinding }
        let rack = analysis.events.first { $0.kind == .rackIt }
        XCTAssertNotNil(grind)
        XCTAssertNotNil(rack)
        if let g = grind, let r = rack {
            XCTAssertLessThanOrEqual(g.timestamp, r.timestamp, "grind must precede RACK IT")
            XCTAssertGreaterThan(r.confidence, g.confidence)
        }
        XCTAssertTrue(analysis.reps.contains { $0.reachedRackIt })
    }

    // MARK: - Engine: squat path (no velocity, no mid-rep manual input — ADR 0005)

    private func squatCalibration() -> CalibrationValues {
        Calibration().calibrate(lift: .squat, warmupMotion: cleanSet(reps: 3, amplitude: 0.4, concentric: 0.9))
    }

    /// An extreme tempo blowout (ratio past `rackDurationMultiplier`) must
    /// reach RACK IT entirely on its own — no HR, no tap (there is no tap).
    func testSquatExtremeTempoBlowoutFiresRackItWithNoHR() {
        let calib = squatCalibration()

        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.4, duration: 0.9)   // eccentric
        b.bump(amplitude: 0.6, duration: 2.2)    // extreme tempo blowout: ratio well past T2
        b.still(0.4)

        let engine = SpotEngine(lift: .squat, calibration: calib)
        let analysis = engine.process(motion: b.samples) // no hr at all

        XCTAssertFalse(analysis.usedVelocityPath, "squat must NOT use the velocity path")
        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding }, "extreme tempo blowout must fire Stage 1")
        XCTAssertTrue(analysis.events.contains { $0.kind == .rackIt }, "an extreme blowout alone must escalate to RACK IT with zero HR data")
        XCTAssertEqual(analysis.events.first { $0.kind == .rackIt }?.reason, .sustainedPin, "driven by tempo alone, not HR")
    }

    /// A moderate tempo blowout (past T1 but not past T2) needs the
    /// corroborating HR spike to escalate; tempo alone would only be Stage 1.
    func testSquatModerateTempoWithHRSpikeFiresRackIt() {
        let calib = squatCalibration()

        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.4, duration: 0.9)   // eccentric
        b.bump(amplitude: 0.3, duration: 1.6)    // moderate tempo grind: ratio ≈ 1.78
        b.still(0.4)
        let motion = b.samples

        let hr: [HRSample] = [
            HRSample(timestamp: 0.1, beatsPerMinute: 120),
            HRSample(timestamp: 0.3, beatsPerMinute: 121),
            HRSample(timestamp: 1.6, beatsPerMinute: 162),
            HRSample(timestamp: 2.2, beatsPerMinute: 168),
        ]

        let engine = SpotEngine(lift: .squat, calibration: calib)
        let analysis = engine.process(motion: motion, hr: hr)

        XCTAssertFalse(analysis.usedVelocityPath, "squat must NOT use the velocity path")
        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding }, "moderate tempo drift must fire Stage 1")
        XCTAssertTrue(analysis.events.contains { $0.kind == .rackIt }, "moderate tempo + HR spike must escalate to RACK IT")
        XCTAssertEqual(analysis.events.first { $0.kind == .rackIt }?.reason, .hrSpike, "the HR spike is what tipped this one")
    }

    /// A clean squat rep at normal tempo with no HR spike must stay silent —
    /// the false-alarm guard, now with no manual tap to lean on either.
    func testSquatCleanRepStaysSilent() {
        let calib = squatCalibration()
        let motion = cleanSet(reps: 3, amplitude: 0.4, concentric: 0.9)

        let engine = SpotEngine(lift: .squat, calibration: calib)
        let analysis = engine.process(motion: motion)

        XCTAssertFalse(analysis.usedVelocityPath, "squat must NOT use the velocity path for its trigger")
        XCTAssertTrue(analysis.events.isEmpty, "a clean squat set must not fire any event; got \(analysis.events)")
        XCTAssertFalse(analysis.reps.contains { $0.flaggedStall })
    }

    // MARK: - Engine: squat velocity (ADR 0009 — computed, but does not trigger)

    /// Squat's wrist rides the bar (ADR 0009), so `SpotEngine` must now report
    /// real Mean/Peak Concentric Velocity and displacement for squat reps —
    /// even though the trigger stays tempo/HR (`usedVelocityPath` is false).
    func testSquatComputesVelocity() {
        let calib = squatCalibration()
        let motion = cleanSet(reps: 3, amplitude: 0.4, concentric: 0.9)

        let engine = SpotEngine(lift: .squat, calibration: calib)
        let analysis = engine.process(motion: motion)

        XCTAssertFalse(analysis.usedVelocityPath, "squat's trigger still must not be velocity-driven")
        XCTAssertEqual(analysis.reps.count, 3)
        for rep in analysis.reps {
            XCTAssertGreaterThan(rep.meanVelocityMS, 0, "squat velocity should now be computed, not hardcoded to 0")
            XCTAssertGreaterThan(rep.peakVelocityMS, 0)
            XCTAssertGreaterThan(rep.displacementM, 0)
        }
    }

    /// A squat rep with a normal tempo but a deliberately weak/slow bar speed
    /// must NOT alarm: velocity is reported but must never feed the squat
    /// trigger, which stays tempo + HR only (ADR 0009).
    func testSquatNormalTempoLowVelocityDoesNotAlarm() {
        let calib = squatCalibration()

        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.2, duration: 0.9)   // eccentric
        b.bump(amplitude: 0.2, duration: 0.9)    // normal tempo, deliberately weak bar speed
        b.still(0.4)

        let engine = SpotEngine(lift: .squat, calibration: calib)
        let analysis = engine.process(motion: b.samples)

        XCTAssertFalse(analysis.usedVelocityPath)
        XCTAssertGreaterThan(analysis.reps.first?.meanVelocityMS ?? 0, 0, "velocity is still reported")
        XCTAssertLessThan(analysis.reps.first?.meanVelocityMS ?? 0, 0.15, "velocity should read as weak/slow")
        XCTAssertTrue(analysis.events.isEmpty, "low velocity alone must not trigger a squat alert; got \(analysis.events)")
        XCTAssertFalse(analysis.reps.contains { $0.flaggedStall })
    }

    /// A squat rep with fast bar speed but a blown tempo must still RACK IT:
    /// tempo alone drives the squat trigger, regardless of how fast the
    /// (now-computed) velocity number looks.
    func testSquatFastVelocityWithBlownTempoStillRacksIt() {
        let calib = squatCalibration()

        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.4, duration: 0.9)   // eccentric
        b.bump(amplitude: 1.2, duration: 2.2)    // fast bar speed, but still an extreme tempo blowout
        b.still(0.4)

        let engine = SpotEngine(lift: .squat, calibration: calib)
        let analysis = engine.process(motion: b.samples) // no hr at all

        XCTAssertFalse(analysis.usedVelocityPath, "squat must NOT use the velocity path")
        XCTAssertGreaterThan(analysis.reps.first?.meanVelocityMS ?? 0, 0.3, "velocity should read as fast, not suppressed")
        XCTAssertTrue(analysis.events.contains { $0.kind == .rackIt }, "tempo blowout must still escalate to RACK IT even with a fast velocity reading")
        XCTAssertEqual(analysis.events.first { $0.kind == .rackIt }?.reason, .sustainedPin, "driven by tempo, never by velocity")
    }
}
