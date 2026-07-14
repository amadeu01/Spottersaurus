//
//  RawSetCaptureRecorderTests.swift
//  SpottersaurusKitTests
//
//  Locks the pure arm→end accumulator (PRC-2 / ADR 0008): buffer assembly,
//  the seeded `.armed` boundary, marker-timeline ordering on the
//  seconds-since-armed clock, that `begin` clears the previous set (bounded
//  memory), and that appends/marks made while idle are dropped.
//

import XCTest
@testable import SpottersaurusKit

final class RawSetCaptureRecorderTests: XCTestCase {

    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let setID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private let armedAt = Date(timeIntervalSince1970: 1_752_000_000)

    private func motion(_ t: TimeInterval) -> DeviceMotionSample {
        DeviceMotionSample(
            timestamp: t,
            userAccelerationG: Vector3(x: 0.1, y: 0.2, z: 0.3),
            gravityG: Vector3(x: 0, y: 0, z: -1),
            rotationRateRadS: Vector3(x: 0.01, y: 0.02, z: 0.03),
            attitude: Quaternion(w: 1, x: 0, y: 0, z: 0)
        )
    }

    private func begin(_ recorder: RawSetCaptureRecorder, setIndex: Int = 2, setCount: Int = 5, lift: LiftKind = .bench) {
        recorder.begin(
            sessionID: sessionID,
            setID: setID,
            setIndex: setIndex,
            setCount: setCount,
            lift: lift,
            armedAt: armedAt
        )
    }

    // MARK: - Identity + armed boundary

    func testBeginSeedsArmedMarkerAtZeroAndCarriesIdentity() throws {
        let recorder = RawSetCaptureRecorder()
        XCTAssertFalse(recorder.isRecording)

        begin(recorder, setIndex: 3, setCount: 6, lift: .squat)
        XCTAssertTrue(recorder.isRecording)

        let capture = try XCTUnwrap(recorder.finish())
        XCTAssertEqual(capture.sessionID, sessionID)
        XCTAssertEqual(capture.setID, setID)
        XCTAssertEqual(capture.setIndex, 3)
        XCTAssertEqual(capture.setCount, 6)
        XCTAssertEqual(capture.lift, .squat)
        XCTAssertEqual(capture.armedAt, armedAt)
        XCTAssertEqual(capture.schemaVersion, RawSetCapture.currentSchemaVersion)
        XCTAssertEqual(capture.markers, [CaptureMarker(timestamp: 0, kind: .armed)])
    }

    // MARK: - Buffer assembly (arrival order)

    func testMotionAndHeartRateAccumulateInArrivalOrder() throws {
        let recorder = RawSetCaptureRecorder()
        begin(recorder)

        recorder.appendMotion([motion(0.0), motion(0.005)])
        recorder.appendMotion([])                 // empty batch is a no-op
        recorder.appendMotion([motion(0.010)])
        recorder.appendHeartRate(HRSample(timestamp: 0.0, beatsPerMinute: 118))
        recorder.appendHeartRate(HRSample(timestamp: 1.0, beatsPerMinute: 121))

        let capture = try XCTUnwrap(recorder.finish())
        XCTAssertEqual(capture.motion.map(\.timestamp), [0.0, 0.005, 0.010])
        XCTAssertEqual(capture.heartRate.map(\.beatsPerMinute), [118, 121])
    }

    // MARK: - Marker timeline (seconds-since-armed clock)

    func testMarkerTimelinePreservesOrderAndClock() throws {
        let recorder = RawSetCaptureRecorder()
        begin(recorder)

        recorder.mark(.settling, at: 0.4)
        recorder.mark(.firstRep, at: 1.1)
        recorder.mark(.rep, at: 2.3)
        recorder.mark(.racked, at: 3.6)
        recorder.mark(.restStarted, at: 3.7)
        recorder.mark(.ended, at: 93.7)

        let capture = try XCTUnwrap(recorder.finish())
        XCTAssertEqual(capture.markers, [
            CaptureMarker(timestamp: 0.0, kind: .armed),
            CaptureMarker(timestamp: 0.4, kind: .settling),
            CaptureMarker(timestamp: 1.1, kind: .firstRep),
            CaptureMarker(timestamp: 2.3, kind: .rep),
            CaptureMarker(timestamp: 3.6, kind: .racked),
            CaptureMarker(timestamp: 3.7, kind: .restStarted),
            CaptureMarker(timestamp: 93.7, kind: .ended)
        ])
    }

    func testMarkClampsNegativeTimestampToZero() throws {
        let recorder = RawSetCaptureRecorder()
        begin(recorder)
        recorder.mark(.settling, at: -0.002)     // origin skew must not go before armed

        let capture = try XCTUnwrap(recorder.finish())
        XCTAssertEqual(capture.markers.last, CaptureMarker(timestamp: 0, kind: .settling))
    }

    // MARK: - Bounded memory: begin clears the previous set

    func testBeginClearsPreviousSet() throws {
        let recorder = RawSetCaptureRecorder()

        // Set A: fill it with samples and markers, then re-begin WITHOUT
        // finishing (the "abandoned set" path) — nothing from A may survive.
        let otherSetID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        recorder.begin(sessionID: sessionID, setID: otherSetID, setIndex: 0, setCount: 5, lift: .deadlift, armedAt: armedAt)
        recorder.appendMotion([motion(0.0), motion(0.005), motion(0.010)])
        recorder.appendHeartRate(HRSample(timestamp: 0.0, beatsPerMinute: 110))
        recorder.mark(.settling, at: 0.5)

        // Set B: a fresh set.
        begin(recorder, setIndex: 2, setCount: 5, lift: .bench)
        recorder.appendMotion([motion(0.02)])

        let capture = try XCTUnwrap(recorder.finish())
        XCTAssertEqual(capture.setID, setID)
        XCTAssertEqual(capture.setIndex, 2)
        XCTAssertEqual(capture.lift, .bench)
        XCTAssertEqual(capture.motion.map(\.timestamp), [0.02])
        XCTAssertEqual(capture.heartRate, [])
        // Only B's seeded armed marker — none of A's settling.
        XCTAssertEqual(capture.markers, [CaptureMarker(timestamp: 0, kind: .armed)])
    }

    // MARK: - Idle guards

    func testAppendsAndMarksBeforeBeginAreDropped() {
        let recorder = RawSetCaptureRecorder()
        recorder.appendMotion([motion(0.0)])
        recorder.appendHeartRate(HRSample(timestamp: 0.0, beatsPerMinute: 100))
        recorder.mark(.settling, at: 0.1)

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.finish())
    }

    func testFinishStopsRecordingAndSecondFinishReturnsNil() throws {
        let recorder = RawSetCaptureRecorder()
        begin(recorder)

        XCTAssertNotNil(recorder.finish())
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.finish())

        // Appends after finish (before the next begin) are dropped too.
        recorder.appendMotion([motion(0.0)])
        XCTAssertNil(recorder.finish())
    }

    // MARK: - Round-trips through the format codec

    func testFinishedCaptureRoundTripsThroughBinaryCodec() throws {
        let recorder = RawSetCaptureRecorder()
        begin(recorder)
        recorder.appendMotion([motion(0.0), motion(0.005)])
        recorder.appendHeartRate(HRSample(timestamp: 0.0, beatsPerMinute: 120))
        recorder.mark(.settling, at: 0.3)
        recorder.mark(.firstRep, at: 1.0)
        recorder.mark(.ended, at: 42.0)

        let capture = try XCTUnwrap(recorder.finish())
        let decoded = try RawSetCapture(decoded: capture.encoded())
        XCTAssertEqual(decoded, capture)
    }
}
