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

    // MARK: - Engine: squat path (no velocity)

    func testSquatUsesTempoHRTapNotVelocity() {
        // Warmup baseline for squat tempo.
        let calib = Calibration().calibrate(lift: .squat, warmupMotion: cleanSet(reps: 3, amplitude: 0.4, concentric: 0.9))

        // A slow squat rep with a manual grind tap + an HR spike during the rep.
        var b = MotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.4, duration: 0.9)   // eccentric
        b.bump(amplitude: 0.3, duration: 1.6)    // slow concentric (tempo grind)
        b.still(0.4)
        let motion = b.samples

        let hr: [HRSample] = [
            HRSample(timestamp: 0.1, beatsPerMinute: 120),
            HRSample(timestamp: 0.3, beatsPerMinute: 121),
            HRSample(timestamp: 1.6, beatsPerMinute: 162),
            HRSample(timestamp: 2.2, beatsPerMinute: 168),
        ]
        let taps: [TimeInterval] = [2.0]

        let engine = SpotEngine(lift: .squat, calibration: calib)
        let analysis = engine.process(motion: motion, hr: hr, manualTaps: taps)

        XCTAssertFalse(analysis.usedVelocityPath, "squat must NOT use the velocity path")
        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding }, "squat tempo/HR/tap must fire Stage 1")
        // The velocity path is disabled: no VBT numbers should be reported.
        XCTAssertTrue(analysis.reps.allSatisfy { $0.meanVelocityMS == 0 && $0.peakVelocityMS == 0 })
    }
}
