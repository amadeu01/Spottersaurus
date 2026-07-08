//
//  SyncEnvelopeTests.swift
//  SpottersaurusKitTests
//
//  TDD coverage for the Watch <-> iPhone sync DTOs: Codable round-trips
//  through the public API (encode -> decode -> Equatable), ISO-8601 date
//  survival, and the small pieces of derived behavior the envelopes carry
//  (e1RM, tonnage).
//

import XCTest
@testable import SpottersaurusKit

final class SyncEnvelopeTests: XCTestCase {

    /// Encoder/decoder pair matching the app's default JSON configuration for
    /// this sync layer: ISO-8601 dates (WatchConnectivity payloads are JSON;
    /// `.iso8601` is the encoder default this app standardizes on, since the
    /// bare `JSONEncoder()`/`JSONDecoder()` strategy — a raw reference-date
    /// double — is not human-legible on the wire).
    private func makeCoders() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let (encoder, decoder) = makeCoders()
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: RepMetricEnvelope

    func testRepMetricEnvelopeRoundTrips() throws {
        let metric = RepMetricEnvelope(
            repIndex: 1,
            concentricSeconds: 1.35,
            peakVelocityMS: 0.62,
            meanVelocityMS: 0.41,
            romProxy: 0.87,
            flaggedStall: true
        )

        let decoded = try roundTrip(metric)
        XCTAssertEqual(decoded, metric)
    }

    // MARK: SpotEventEnvelope

    func testSpotEventEnvelopeRoundTrips() throws {
        let event = SpotEventEnvelope(
            stage: .rackIt,
            timestamp: 12.4,
            repIndex: 2,
            confidence: 0.91,
            reason: .sustainedPin
        )

        let decoded = try roundTrip(event)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.stage, .rackIt)
        XCTAssertEqual(decoded.reason, .sustainedPin)
    }

    // MARK: CalibrationEnvelope

    func testCalibrationEnvelopeRoundTripsAndSurvivesISO8601Date() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_732_000_000)
        let calibration = CalibrationEnvelope(
            lift: .bench,
            baselineConcentricSeconds: 1.1,
            velocityBandLowerMS: 0.25,
            velocityBandUpperMS: 0.55,
            repCount: 3,
            capturedAt: capturedAt
        )

        let (encoder, _) = makeCoders()
        let data = try encoder.encode(calibration)
        // ISO-8601 (RFC 3339) — a plain double timestamp would not contain "T".
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("T"), "expected ISO-8601 date string, got: \(json)")

        let decoded = try roundTrip(calibration)
        XCTAssertEqual(decoded, calibration)
        XCTAssertEqual(decoded.capturedAt.timeIntervalSince1970, capturedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: LiveTickEnvelope

    func testLiveTickEnvelopeRoundTrips() throws {
        let tick = LiveTickEnvelope(
            repCount: 3,
            currentVelocityMS: 0.34,
            heartRateBPM: 142,
            elapsedSeconds: 18.7
        )

        let decoded = try roundTrip(tick)
        XCTAssertEqual(decoded, tick)
    }

    // MARK: CompletedSetEnvelope — richer fields

    /// The pre-existing scaffold init (no rep metrics / spotter events / e1RM
    /// inputs) must keep compiling untouched — new params are additive with
    /// defaults, not a breaking signature change.
    func testCompletedSetEnvelopeOldInitStillCompiles() {
        let legacy = CompletedSetEnvelope(
            lift: .deadlift,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            weightKg: 180,
            repsCompleted: 3
        )
        XCTAssertEqual(legacy.repMetrics, [])
        XCTAssertEqual(legacy.spotEvents, [])
        XCTAssertEqual(legacy.avgConcentricVelocityMS, 0)
        XCTAssertEqual(legacy.peakConcentricVelocityMS, 0)
    }

    func testCompletedSetEnvelopeRoundTripsWithRepMetricsAndSpotEvents() throws {
        let set = CompletedSetEnvelope(
            lift: .bench,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            weightKg: 100,
            repsCompleted: 2,
            repMetrics: [
                RepMetricEnvelope(repIndex: 0, concentricSeconds: 1.0, peakVelocityMS: 0.6, meanVelocityMS: 0.45),
                RepMetricEnvelope(repIndex: 1, concentricSeconds: 1.6, peakVelocityMS: 0.3, meanVelocityMS: 0.2, flaggedStall: true),
            ],
            spotEvents: [
                SpotEventEnvelope(stage: .grinding, timestamp: 6.2, repIndex: 1, confidence: 0.6, reason: .concentricTempo),
            ],
            avgConcentricVelocityMS: 0.325,
            peakConcentricVelocityMS: 0.6
        )

        let decoded = try roundTrip(set)
        XCTAssertEqual(decoded, set)
        XCTAssertEqual(decoded.repMetrics.count, 2)
        XCTAssertEqual(decoded.spotEvents.first?.reason, .concentricTempo)
    }

    // MARK: e1RM

    func testCompletedSetEnvelopeEstimatedOneRepMax() {
        // Epley: 100 * (1 + 5/30) = 116.666...
        let set = CompletedSetEnvelope(
            lift: .squat,
            startedAt: Date(),
            weightKg: 100,
            repsCompleted: 5
        )
        XCTAssertEqual(set.estimatedOneRepMaxKg, 116.7, accuracy: 0.05)
    }

    // MARK: SessionEnvelope tonnage with richer sets

    func testSessionEnvelopeTotalTonnageWithRicherSets() {
        let setA = CompletedSetEnvelope(
            lift: .squat,
            startedAt: Date(),
            weightKg: 100,
            repsCompleted: 5,
            repMetrics: [RepMetricEnvelope(repIndex: 0, concentricSeconds: 1.0, peakVelocityMS: 0.5, meanVelocityMS: 0.4)],
            avgConcentricVelocityMS: 0.4,
            peakConcentricVelocityMS: 0.5
        )
        let setB = CompletedSetEnvelope(
            lift: .bench,
            startedAt: Date(),
            weightKg: 60,
            repsCompleted: 8
        )
        let session = SessionEnvelope(date: Date(), sets: [setA, setB])

        // 100*5 + 60*8 = 980
        XCTAssertEqual(session.totalTonnageKg, 980, accuracy: 0.0001)
    }
}
