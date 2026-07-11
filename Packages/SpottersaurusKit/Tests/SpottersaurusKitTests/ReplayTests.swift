//
//  ReplayTests.swift
//  SpottersaurusKitTests
//
//  PRC-4 (ADR 0008): replaying a stored `RawSetCapture` back through
//  `SpotEngine` must deterministically reproduce its events/metrics. This
//  also exercises the new `SpotEngine.process(deviceMotion:hr:)` entry point
//  (ADR 0007) that `replay` drives, and locks in that it shares its
//  downstream analysis with the existing `process(motion:hr:)` raw-accel
//  path — no duplicated analyze logic. No CoreMotion, no hardware.
//

import XCTest
import Foundation
@testable import SpottersaurusKit

final class ReplayTests: XCTestCase {

    // MARK: - Synthetic device-motion fixture builder
    //
    // Mirrors `DetectionTests.MotionBuilder` but emits `DeviceMotionSample`s
    // directly in the fused shape: `userAccelerationG` carries only the
    // gravity-removed linear signal (no +1g offset), and `gravityG` is the
    // constant CoreMotion-convention down vector (0, 0, -1) for a device
    // held flat. `GravityRemover.axialAcceleration(deviceMotion:)` projects
    // these onto -gravity, landing on the exact same up-positive axial
    // convention the raw front end produces.

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

        /// A velocity bump v(τ) = A·sin²(π τ/T): acceleration is the
        /// derivative, a full sine period returning the bar to rest. A>0 is
        /// concentric (up), A<0 eccentric (down).
        mutating func bump(amplitude A: Double, duration T: Double) {
            var local = 0.0
            while local < T {
                let a = A * (Double.pi / T) * sin(2 * Double.pi * local / T)
                append(uaZ: a / g)
                local += dt
            }
        }

        /// An isometric grind: small jittery acceleration (bar stuck mid-rep,
        /// integrates to ~zero velocity).
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
            b.bump(amplitude: -A, duration: T)   // eccentric (down)
            b.bump(amplitude: A, duration: T)    // concentric (up)
            b.still(0.4)
        }
        return b.samples
    }

    /// One slow-but-completed grind rep (Stage-1 territory, no pin).
    private func grindDeviceMotion() -> [DeviceMotionSample] {
        var b = DeviceMotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.5, duration: 0.8)   // eccentric
        b.bump(amplitude: 0.28, duration: 1.5)   // slow concentric, still completes
        b.still(0.4)
        return b.samples
    }

    /// One pinned rep: rises partway, then the bar stalls (no lockout).
    private func pinDeviceMotion() -> [DeviceMotionSample] {
        var b = DeviceMotionBuilder()
        b.still(0.4)
        b.bump(amplitude: -0.5, duration: 0.8)   // eccentric
        b.bump(amplitude: 0.45, duration: 0.6)   // partial concentric
        b.grindPlateau(1.8)                      // stuck mid-rep, no lockout
        b.still(0.4)
        return b.samples
    }

    /// The raw-accelerometer equivalent of `cleanDeviceMotion`, used only to
    /// prove the two front ends agree — same shape as `DetectionTests`'s
    /// fixture builder, kept file-local so test files stay independent.
    private func cleanRawMotion(reps n: Int, amplitude A: Double = 0.5, concentric T: Double = 0.8) -> [MotionSample] {
        let dt = 0.02
        let g = standardGravityMS2
        var samples: [MotionSample] = []
        var t = 0.0

        func still(_ duration: Double) {
            var local = 0.0
            while local < duration {
                samples.append(MotionSample(timestamp: t, accelX: 0, accelY: 0, accelZ: 1.0))
                t += dt; local += dt
            }
        }
        func bump(amplitude A: Double, duration T: Double) {
            var local = 0.0
            while local < T {
                let a = A * (Double.pi / T) * sin(2 * Double.pi * local / T)
                samples.append(MotionSample(timestamp: t, accelX: 0, accelY: 0, accelZ: 1.0 + a / g))
                t += dt; local += dt
            }
        }

        still(0.4)
        for _ in 0..<n {
            bump(amplitude: -A, duration: T)
            bump(amplitude: A, duration: T)
            still(0.4)
        }
        return samples
    }

    private func makeBenchCalibration() -> CalibrationValues {
        Calibration().calibrate(lift: .bench, warmupMotion: cleanRawMotion(reps: 3))
    }

    private func makeCapture(
        lift: LiftKind = .bench,
        motion: [DeviceMotionSample],
        heartRate: [HRSample] = []
    ) -> RawSetCapture {
        RawSetCapture(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            setID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            setIndex: 0,
            setCount: 1,
            lift: lift,
            armedAt: Date(timeIntervalSince1970: 1_752_000_000),
            motion: motion,
            heartRate: heartRate,
            markers: []
        )
    }

    // MARK: - process(deviceMotion:) shares the downstream with process(motion:)

    /// A clean device-motion set must stay silent through the new entry
    /// point, exactly as the raw path does — the false-alarm guard applies
    /// to both front ends via the shared downstream.
    func testProcessDeviceMotionCleanRepsFireNoEvents() {
        let engine = SpotEngine(lift: .bench, calibration: makeBenchCalibration())
        let analysis = engine.process(deviceMotion: cleanDeviceMotion(reps: 3))

        XCTAssertTrue(analysis.usedVelocityPath)
        XCTAssertEqual(analysis.reps.count, 3)
        XCTAssertTrue(analysis.events.isEmpty, "clean reps must not fire any event; got \(analysis.events)")
    }

    /// A grind fed through `process(deviceMotion:)` must fire the same
    /// Stage 1 grinding nudge the raw-accel path fires for its equivalent
    /// buffer — proof the two entry points share one downstream, not a
    /// forked copy.
    func testProcessDeviceMotionGrindFiresStageOne() {
        let engine = SpotEngine(lift: .bench, calibration: makeBenchCalibration())
        let analysis = engine.process(deviceMotion: grindDeviceMotion())

        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding }, "a slow grind must fire Stage 1 via the device-motion entry point")
        XCTAssertFalse(analysis.events.contains { $0.kind == .rackIt })
    }

    /// A hard pin fed through `process(deviceMotion:)` must escalate to
    /// Stage 2, exactly as it does through the raw-accel entry point.
    func testProcessDeviceMotionHardPinFiresStageTwo() {
        let engine = SpotEngine(lift: .bench, calibration: makeBenchCalibration())
        let analysis = engine.process(deviceMotion: pinDeviceMotion())

        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding })
        XCTAssertTrue(analysis.events.contains { $0.kind == .rackIt }, "a hard pin must escalate to RACK IT via the device-motion entry point")
    }

    /// The device-motion path and an equivalent raw-accelerometer path must
    /// agree on rep count for the same physical set (sign/scale already
    /// reconciled by the P15-S1 fused front end).
    func testDeviceMotionAndRawPathsAgreeOnRepCount() {
        let calib = makeBenchCalibration()
        let engine = SpotEngine(lift: .bench, calibration: calib)

        let rawAnalysis = engine.process(motion: cleanRawMotion(reps: 4))
        let fusedAnalysis = engine.process(deviceMotion: cleanDeviceMotion(reps: 4))

        XCTAssertEqual(rawAnalysis.reps.count, 4)
        XCTAssertEqual(fusedAnalysis.reps.count, rawAnalysis.reps.count, "device-motion and raw-accel paths must agree on rep count for an equivalent set")
    }

    // MARK: - Replay: determinism

    /// Replaying the same capture twice with the same calibration/config
    /// must yield an exactly equal `SpotAnalysis` — the core debug/tuning
    /// loop depends on this being a pure, repeatable function.
    func testReplayIsDeterministic() {
        let capture = makeCapture(motion: grindDeviceMotion())
        let calib = makeBenchCalibration()

        let first = SpotEngine.replay(capture, calibration: calib)
        let second = SpotEngine.replay(capture, calibration: calib)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.events.isEmpty, "sanity: the grind fixture should actually produce events to compare")
    }

    // MARK: - Replay: reproduces expected events/metrics

    /// Replaying a capture built from clean device-motion reps must yield
    /// the expected rep count with no false-alarm events.
    func testReplayOfCleanCaptureYieldsExpectedRepCountNoEvents() {
        let capture = makeCapture(motion: cleanDeviceMotion(reps: 3))
        let analysis = SpotEngine.replay(capture, calibration: makeBenchCalibration())

        XCTAssertEqual(analysis.reps.count, 3)
        XCTAssertTrue(analysis.events.isEmpty)
    }

    /// Replaying a capture built from a synthetic grind must yield at least
    /// one detection event (the core debug loop: reproduce what the live
    /// engine would have flagged).
    func testReplayOfGrindCaptureProducesAtLeastOneEvent() {
        let capture = makeCapture(motion: grindDeviceMotion())
        let analysis = SpotEngine.replay(capture, calibration: makeBenchCalibration())

        XCTAssertFalse(analysis.events.isEmpty, "replaying a grind capture must reproduce at least one spot event")
        XCTAssertTrue(analysis.events.contains { $0.kind == .grinding })
    }

    /// Replay reads `lift` from the capture itself (not a caller-supplied
    /// value): a squat capture must produce a squat-shaped analysis
    /// (`usedVelocityPath == false`) even though every other fixture here is
    /// bench.
    func testReplayUsesLiftFromCapture() {
        let squatMotion = cleanDeviceMotion(reps: 3, amplitude: 0.4, concentric: 0.9)
        let capture = makeCapture(lift: .squat, motion: squatMotion)

        let analysis = SpotEngine.replay(capture)

        XCTAssertFalse(analysis.usedVelocityPath, "a squat capture must replay through the tempo/HR path, not velocity")
        XCTAssertEqual(analysis.reps.count, 3)
    }

    /// With no explicit `calibration` argument, replay must fall back to
    /// `CalibrationValues.fallback(for: capture.lift)` rather than crashing
    /// or silently using an all-zero baseline (a capture does not yet carry
    /// its own calibration snapshot — see ADR 0008/PRC-4).
    func testReplayDefaultsToFallbackCalibrationForCaptureLift() {
        let capture = makeCapture(lift: .deadlift, motion: cleanDeviceMotion(reps: 2))

        let analysis = SpotEngine.replay(capture)
        let expected = SpotEngine(lift: .deadlift, calibration: .fallback(for: .deadlift))
            .process(deviceMotion: capture.motion, hr: capture.heartRate)

        XCTAssertEqual(analysis, expected)
    }
}
