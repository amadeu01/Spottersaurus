//
//  PersistenceMappingTests.swift
//  SpottersaurusKitTests
//
//  TDD coverage for the envelope -> SwiftData mapping layer: the Watch -> iPhone
//  finished-session handoff landing step. Exercises `SessionImporter` against an
//  in-memory, CloudKit-off container (same pattern as `ModelTests`).
//

import XCTest
import SwiftData
@testable import SpottersaurusKit

@MainActor
final class PersistenceMappingTests: XCTestCase {

    /// A fresh in-memory container per test — no disk, no CloudKit.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try makeModelContainer(inMemory: true, cloudKit: false)
        return (container, ModelContext(container))
    }

    // MARK: basic import

    func testImportingEnvelopeCreatesWorkoutSessionWithCompletedSet() throws {
        let (_, context) = try makeContext()

        let envelope = SessionEnvelope(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                CompletedSetEnvelope(
                    lift: .bench,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    weightKg: 100,
                    repsCompleted: 5
                ),
            ]
        )

        let session = try SessionImporter.importSession(envelope, into: context)

        XCTAssertEqual(session.id, envelope.id)
        XCTAssertEqual(session.date, envelope.date)
        XCTAssertEqual(session.completedSets?.count, 1)

        let fetched = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(fetched.count, 1)

        let set = try XCTUnwrap(fetched.first?.completedSets?.first)
        XCTAssertEqual(set.weightKg, 100)
        XCTAssertEqual(set.repsPerformed, 5)
    }

    // MARK: rep order + exercise mapping

    func testImportPreservesRepOrderAndMapsExerciseKind() throws {
        let (_, context) = try makeContext()

        let envelope = SessionEnvelope(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                CompletedSetEnvelope(
                    lift: .deadlift,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    weightKg: 180,
                    repsCompleted: 3,
                    // Deliberately out of order to prove repIndex, not array
                    // position, wins on read-back.
                    repMetrics: [
                        RepMetricEnvelope(repIndex: 2, concentricSeconds: 1.6, peakVelocityMS: 0.3, meanVelocityMS: 0.2, flaggedStall: true),
                        RepMetricEnvelope(repIndex: 0, concentricSeconds: 1.0, peakVelocityMS: 0.6, meanVelocityMS: 0.45),
                        RepMetricEnvelope(repIndex: 1, concentricSeconds: 1.1, peakVelocityMS: 0.55, meanVelocityMS: 0.4),
                    ]
                ),
            ]
        )

        let session = try SessionImporter.importSession(envelope, into: context)

        let set = try XCTUnwrap(session.completedSets?.first)
        XCTAssertEqual(set.exercise?.kind, .deadlift)

        let ordered = set.orderedRepMetrics
        XCTAssertEqual(ordered.map(\.repIndex), [0, 1, 2])
        XCTAssertEqual(ordered.map(\.concentricSeconds), [1.0, 1.1, 1.6])
        XCTAssertEqual(ordered.last?.flaggedStall, true)
    }

    // MARK: spotter events

    func testImportMapsGrindAndRackItSpotEventsButSkipsResolved() throws {
        let (_, context) = try makeContext()

        let envelope = SessionEnvelope(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                CompletedSetEnvelope(
                    lift: .bench,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    weightKg: 100,
                    repsCompleted: 1,
                    spotEvents: [
                        SpotEventEnvelope(stage: .grinding, timestamp: 3.1, repIndex: 0, confidence: 0.6, reason: .concentricTempo),
                        SpotEventEnvelope(stage: .rackIt, timestamp: 4.2, repIndex: 0, confidence: 0.95, reason: .sustainedPin),
                        // `.resolved` clears in-flight state on the Watch; it has no
                        // corresponding `SpotterEvent.Stage` and must not persist.
                        SpotEventEnvelope(stage: .resolved, timestamp: 4.2, repIndex: 0, confidence: 0.5, reason: .lockout),
                    ]
                ),
            ]
        )

        let session = try SessionImporter.importSession(envelope, into: context)
        let set = try XCTUnwrap(session.completedSets?.first)

        XCTAssertEqual(set.spotterEvents.count, 2)
        XCTAssertEqual(set.spotterEvents.map(\.stage), [.grind, .rackIt])
        XCTAssertEqual(set.spotterEvents.map(\.timestamp), [3.1, 4.2])
        XCTAssertEqual(set.spotterEvents.map(\.repIndex), [0, 0])
    }

    // MARK: idempotency

    func testReimportingSameEnvelopeIDDoesNotDuplicate() throws {
        let (_, context) = try makeContext()

        let envelope = SessionEnvelope(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                CompletedSetEnvelope(
                    lift: .squat,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    weightKg: 140,
                    repsCompleted: 5,
                    repMetrics: [
                        RepMetricEnvelope(repIndex: 0, concentricSeconds: 1.2, peakVelocityMS: 0.4, meanVelocityMS: 0.3),
                    ]
                ),
            ]
        )

        try SessionImporter.importSession(envelope, into: context)
        try SessionImporter.importSession(envelope, into: context) // re-delivered, e.g. WatchConnectivity retry

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSet>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RepMetric>()), 1)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.first?.completedSets?.first?.weightKg, 140)
    }

    func testReimportingWithChangedContentUpdatesInPlace() throws {
        let (_, context) = try makeContext()
        let id = UUID()

        let original = SessionEnvelope(
            id: id,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                CompletedSetEnvelope(lift: .bench, startedAt: Date(timeIntervalSince1970: 1_700_000_100), weightKg: 80, repsCompleted: 5),
            ]
        )
        let corrected = SessionEnvelope(
            id: id,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                CompletedSetEnvelope(lift: .bench, startedAt: Date(timeIntervalSince1970: 1_700_000_100), weightKg: 85, repsCompleted: 5),
                CompletedSetEnvelope(lift: .bench, startedAt: Date(timeIntervalSince1970: 1_700_000_300), weightKg: 85, repsCompleted: 3),
            ]
        )

        try SessionImporter.importSession(original, into: context)
        try SessionImporter.importSession(corrected, into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSet>()), 2)

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual((session.completedSets ?? []).map(\.weightKg).sorted(), [85, 85])
    }

    // MARK: empty-sets edge case

    func testImportingEnvelopeWithNoSetsCreatesEmptySession() throws {
        let (_, context) = try makeContext()

        let envelope = SessionEnvelope(date: Date(timeIntervalSince1970: 1_700_000_000), sets: [])
        let session = try SessionImporter.importSession(envelope, into: context)

        XCTAssertEqual(session.completedSets?.count ?? 0, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }
}
