//
//  DeviceMotionSampleTests.swift
//  SpottersaurusKitTests
//
//  ADR 0007: the fused device-motion sample type and its bar-axis front end
//  (`GravityRemover.axialAcceleration(deviceMotion:)`), tested against the
//  raw-accelerometer front end it sits beside. No CoreMotion, no hardware.
//

import XCTest
@testable import SpottersaurusKit

final class DeviceMotionSampleTests: XCTestCase {

    // MARK: - Codable round-trip

    func testDeviceMotionSampleCodableRoundTrip() throws {
        let sample = DeviceMotionSample(
            timestamp: 12.34,
            userAccelerationG: Vector3(x: 0.01, y: -0.02, z: 0.35),
            gravityG: Vector3(x: 0.02, y: -0.01, z: -0.998),
            rotationRateRadS: Vector3(x: 0.1, y: 0.2, z: -0.3),
            attitude: Quaternion(w: 0.999, x: 0.01, y: 0.02, z: 0.03)
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(DeviceMotionSample.self, from: data)

        XCTAssertEqual(decoded, sample)
    }

    // MARK: - Projection: known vectors

    /// A pure-upward user acceleration with a straight-down gravity vector
    /// (device flat, screen up — CoreMotion's documented `gravity ≈ (0,0,-1)`
    /// pose) must project to a positive axialMS2 of the expected magnitude.
    func testProjectionOfKnownVectorsGivesExpectedMagnitudeAndSign() {
        let sample = DeviceMotionSample(
            timestamp: 0,
            userAccelerationG: Vector3(x: 0, y: 0, z: 0.4),   // 0.4 g straight up
            gravityG: Vector3(x: 0, y: 0, z: -1.0),           // straight down
            rotationRateRadS: .zero,
            attitude: .identity
        )

        let out = GravityRemover.axialAcceleration(deviceMotion: [sample])

        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].timestamp, 0)
        XCTAssertEqual(out[0].axialMS2, 0.4 * standardGravityMS2, accuracy: 1e-9,
                        "pure upward userAcceleration against a downward gravity vector must yield a positive axial reading of the expected magnitude")
    }

    /// A pure-downward user acceleration (eccentric) with the same gravity
    /// vector must yield a negative axialMS2 — the mirror of the case above.
    func testProjectionSignFlipsForDownwardAcceleration() {
        let sample = DeviceMotionSample(
            timestamp: 0,
            userAccelerationG: Vector3(x: 0, y: 0, z: -0.3),
            gravityG: Vector3(x: 0, y: 0, z: -1.0),
            rotationRateRadS: .zero,
            attitude: .identity
        )

        let out = GravityRemover.axialAcceleration(deviceMotion: [sample])

        XCTAssertEqual(out[0].axialMS2, -0.3 * standardGravityMS2, accuracy: 1e-9)
    }

    /// Acceleration orthogonal to gravity (e.g. purely lateral wrist sway)
    /// must project to ~zero axial signal.
    func testProjectionOfOrthogonalAccelerationIsZero() {
        let sample = DeviceMotionSample(
            timestamp: 0,
            userAccelerationG: Vector3(x: 0.5, y: 0, z: 0),
            gravityG: Vector3(x: 0, y: 0, z: -1.0),
            rotationRateRadS: .zero,
            attitude: .identity
        )

        let out = GravityRemover.axialAcceleration(deviceMotion: [sample])

        XCTAssertEqual(out[0].axialMS2, 0, accuracy: 1e-9)
    }

    /// A tilted gravity vector (device not perfectly flat) must still
    /// recover the correct axial component via normalization — only the
    /// component of `userAcceleration` along the true up direction counts.
    func testProjectionNormalizesATiltedGravityVector() {
        // Gravity vector reported with some magnitude drift (not unit length)
        // and tilted into X: still points "down-ish" but scaled to 2x.
        let gravity = Vector3(x: -0.6, y: 0, z: -1.6) // magnitude ≈ 1.709
        let gHat = gravity.normalized
        // Build a userAcceleration purely along the true "up" direction
        // (-gHat) with magnitude 0.5 g, so the expected axial is exactly 0.5g.
        let up = Vector3(x: -gHat.x, y: -gHat.y, z: -gHat.z)
        let userAccel = Vector3(x: up.x * 0.5, y: up.y * 0.5, z: up.z * 0.5)

        let sample = DeviceMotionSample(
            timestamp: 0,
            userAccelerationG: userAccel,
            gravityG: gravity,
            rotationRateRadS: .zero,
            attitude: .identity
        )

        let out = GravityRemover.axialAcceleration(deviceMotion: [sample])

        XCTAssertEqual(out[0].axialMS2, 0.5 * standardGravityMS2, accuracy: 1e-6)
    }

    // MARK: - Agreement with the raw-accelerometer front end

    /// The device-motion front end and the raw-accelerometer front end must
    /// agree in sign for an equivalent synthetic input: a device at rest
    /// (gravity only) that then experiences an upward push. The raw path's
    /// EMA gravity estimate settles on the raw accelerometer's at-rest
    /// reading, which points "up" (+1g on the resting axis); the fused
    /// gravity field points "down" (CoreMotion convention, -1g on the same
    /// axis) — opposite raw vectors, same physical pose — and both front
    /// ends must still land on a positive axialMS2 for the same upward push.
    func testDeviceMotionAndRawFrontEndsAgreeInSignForEquivalentInput() {
        let dt = 0.02
        let g = standardGravityMS2
        let restSamples = 20
        let bumpSamples = 20
        let pushG = 0.4 // extra upward acceleration, in g, during the "push"

        // Raw accelerometer stream: gravity read as +1g on Z at rest (raw
        // accelerometer / reaction-force convention), then an upward push
        // adds positively to Z.
        var motion: [MotionSample] = []
        var t = 0.0
        for _ in 0..<restSamples {
            motion.append(MotionSample(timestamp: t, accelX: 0, accelY: 0, accelZ: 1.0))
            t += dt
        }
        for _ in 0..<bumpSamples {
            motion.append(MotionSample(timestamp: t, accelX: 0, accelY: 0, accelZ: 1.0 + pushG))
            t += dt
        }

        // Equivalent fused stream for the same physical pose and push:
        // gravity is reported pointing down (-1g on Z), userAcceleration is
        // zero at rest and +pushG (true upward acceleration) during the push.
        var deviceMotion: [DeviceMotionSample] = []
        t = 0.0
        for _ in 0..<restSamples {
            deviceMotion.append(DeviceMotionSample(
                timestamp: t,
                userAccelerationG: .zero,
                gravityG: Vector3(x: 0, y: 0, z: -1.0),
                rotationRateRadS: .zero,
                attitude: .identity
            ))
            t += dt
        }
        for _ in 0..<bumpSamples {
            deviceMotion.append(DeviceMotionSample(
                timestamp: t,
                userAccelerationG: Vector3(x: 0, y: 0, z: pushG),
                gravityG: Vector3(x: 0, y: 0, z: -1.0),
                rotationRateRadS: .zero,
                attitude: .identity
            ))
            t += dt
        }

        let rawOut = GravityRemover.axialAcceleration(motion, timeConstant: 2.0)
        let fusedOut = GravityRemover.axialAcceleration(deviceMotion: deviceMotion)

        XCTAssertEqual(rawOut.count, motion.count)
        XCTAssertEqual(fusedOut.count, deviceMotion.count)

        // Both front ends must read ~0 at rest.
        XCTAssertEqual(rawOut.first?.axialMS2 ?? .nan, 0, accuracy: 1e-6)
        XCTAssertEqual(fusedOut.first?.axialMS2 ?? .nan, 0, accuracy: 1e-9)

        // During the push both must be positive (up), same sign.
        let rawDuringPush = rawOut.last!.axialMS2
        let fusedDuringPush = fusedOut.last!.axialMS2
        XCTAssertGreaterThan(rawDuringPush, 0, "raw front end must read positive axial during an upward push")
        XCTAssertGreaterThan(fusedDuringPush, 0, "fused front end must read positive axial during an upward push")

        // The fused front end has no EMA lag, so it should recover the exact
        // push magnitude; the raw front end's EMA estimate is still catching
        // up but must be within the same ballpark and same sign.
        XCTAssertEqual(fusedDuringPush, pushG * g, accuracy: 1e-9)
        XCTAssertGreaterThan(rawDuringPush, 0.5 * fusedDuringPush)
    }
}
