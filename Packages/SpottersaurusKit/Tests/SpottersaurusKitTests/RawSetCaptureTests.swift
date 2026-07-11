//
//  RawSetCaptureTests.swift
//  SpottersaurusKitTests
//
//  Locks the RawSetCapture binary codec (exact round-trip), the
//  backward-compatible decode of an older schema payload, and the
//  NDJSON/CSV export formats (ADR 0008).
//

import XCTest
@testable import SpottersaurusKit

final class RawSetCaptureTests: XCTestCase {

    private func makeMotionSample(_ t: TimeInterval) -> DeviceMotionSample {
        DeviceMotionSample(
            timestamp: t,
            userAccelerationG: Vector3(x: 0.1, y: 0.2, z: 0.3),
            gravityG: Vector3(x: 0, y: 0, z: -1),
            rotationRateRadS: Vector3(x: 0.01, y: 0.02, z: 0.03),
            attitude: Quaternion(w: 1, x: 0, y: 0, z: 0)
        )
    }

    private func makeCapture(markers: [CaptureMarker]? = nil) -> RawSetCapture {
        RawSetCapture(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            setID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            setIndex: 2,
            setCount: 5,
            lift: .bench,
            armedAt: Date(timeIntervalSince1970: 1_752_000_000),
            motion: [makeMotionSample(0.0), makeMotionSample(0.005), makeMotionSample(0.010)],
            heartRate: [HRSample(timestamp: 0.0, beatsPerMinute: 118), HRSample(timestamp: 1.0, beatsPerMinute: 121)],
            markers: markers ?? [
                CaptureMarker(timestamp: 0.0, kind: .armed),
                CaptureMarker(timestamp: 0.4, kind: .settling),
                CaptureMarker(timestamp: 1.1, kind: .firstRep),
                CaptureMarker(timestamp: 2.3, kind: .rep),
                CaptureMarker(timestamp: 3.6, kind: .racked),
                CaptureMarker(timestamp: 3.7, kind: .restStarted),
                CaptureMarker(timestamp: 93.7, kind: .ended)
            ]
        )
    }

    // MARK: - Binary round-trip

    func testEncodedDecodedRoundTripsExactly() throws {
        let capture = makeCapture()
        let data = try capture.encoded()
        let decoded = try RawSetCapture(decoded: data)
        XCTAssertEqual(decoded, capture)
    }

    func testEncodedProducesBinaryPropertyListFormat() throws {
        let data = try makeCapture().encoded()
        var format = PropertyListSerialization.PropertyListFormat.xml
        XCTAssertNoThrow(try PropertyListSerialization.propertyList(from: data, format: &format))
        XCTAssertEqual(format, .binary)
    }

    // MARK: - Backward-compatible decode

    /// Mirrors a hypothetical schema-1 payload from before `markers` existed
    /// — same coding keys as `RawSetCapture` minus `markers`. Encoding this
    /// with the same binary codec and decoding it back through
    /// `RawSetCapture(decoded:)` must succeed with `markers == []`.
    private struct OldSchemaCapture: Encodable {
        var schemaVersion: Int
        var sessionID: UUID
        var setID: UUID
        var setIndex: Int
        var setCount: Int
        var lift: LiftKind
        var armedAt: Date
        var motion: [DeviceMotionSample]
        var heartRate: [HRSample]
        // no `markers` key at all
    }

    func testDecodingOlderSchemaMissingMarkersDefaultsToEmptyArray() throws {
        let old = OldSchemaCapture(
            schemaVersion: 1,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            setID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            setIndex: 0,
            setCount: 3,
            lift: .squat,
            armedAt: Date(timeIntervalSince1970: 1_752_000_000),
            motion: [makeMotionSample(0.0)],
            heartRate: []
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(old)

        let decoded = try RawSetCapture(decoded: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.setCount, 3)
        XCTAssertEqual(decoded.lift, .squat)
        XCTAssertEqual(decoded.motion.count, 1)
        XCTAssertEqual(decoded.heartRate, [])
        XCTAssertEqual(decoded.markers, [])
    }

    // MARK: - NDJSON export

    func testExportNDJSONHasHeaderThenOneLinePerSampleAndMarker() throws {
        let capture = makeCapture()
        let text = capture.exportNDJSON()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        let expectedLineCount = 1 + capture.motion.count + capture.heartRate.count + capture.markers.count
        XCTAssertEqual(lines.count, expectedLineCount)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct TypeTag: Decodable { var type: String }
        let tags = try lines.map { try decoder.decode(TypeTag.self, from: Data($0.utf8)).type }
        XCTAssertEqual(tags.first, "header")
        XCTAssertEqual(tags.filter { $0 == "motion" }.count, capture.motion.count)
        XCTAssertEqual(tags.filter { $0 == "hr" }.count, capture.heartRate.count)
        XCTAssertEqual(tags.filter { $0 == "marker" }.count, capture.markers.count)

        struct HeaderLine: Decodable {
            var type: String
            var schemaVersion: Int
            var sessionID: UUID
            var setID: UUID
            var armedAt: Date
        }
        let header = try decoder.decode(HeaderLine.self, from: Data(lines[0].utf8))
        XCTAssertEqual(header.schemaVersion, capture.schemaVersion)
        XCTAssertEqual(header.sessionID, capture.sessionID)
        XCTAssertEqual(header.setID, capture.setID)
        XCTAssertEqual(header.armedAt, capture.armedAt)

        struct MotionLine: Decodable { var type: String; var t: TimeInterval; var uaX: Double }
        let firstMotionLine = lines[1]
        let motionLine = try decoder.decode(MotionLine.self, from: Data(firstMotionLine.utf8))
        XCTAssertEqual(motionLine.type, "motion")
        XCTAssertEqual(motionLine.t, capture.motion[0].timestamp)
        XCTAssertEqual(motionLine.uaX, capture.motion[0].userAccelerationG.x)
    }

    // MARK: - CSV export

    func testExportCSVHasHeaderAndCorrectColumnCountPerRow() throws {
        let capture = makeCapture()
        let csv = capture.exportCSV()
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        XCTAssertEqual(rows.count, 1 + capture.motion.count)
        XCTAssertEqual(rows[0], "t,uaX,uaY,uaZ,gX,gY,gZ,rrX,rrY,rrZ,qw,qx,qy,qz")

        for row in rows {
            XCTAssertEqual(row.split(separator: ",").count, 14)
        }

        let firstDataColumns = rows[1].split(separator: ",")
        XCTAssertEqual(Double(firstDataColumns[0]), capture.motion[0].timestamp)
        XCTAssertEqual(Double(firstDataColumns[1]), capture.motion[0].userAccelerationG.x)
    }

    func testExportHeartRateCSVHasHeaderAndCorrectColumnCountPerRow() throws {
        let capture = makeCapture()
        let csv = capture.exportHeartRateCSV()
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        XCTAssertEqual(rows.count, 1 + capture.heartRate.count)
        XCTAssertEqual(rows[0], "t,bpm")
        for row in rows {
            XCTAssertEqual(row.split(separator: ",").count, 2)
        }
    }
}
