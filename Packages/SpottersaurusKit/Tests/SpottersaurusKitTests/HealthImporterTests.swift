//
//  HealthImporterTests.swift
//  SpottersaurusKitTests
//
//  TDD for H2: the pure HealthKit-neutral mapping (`HealthWorkoutMapper`) and
//  the injectable `HealthImporter` that reads via a fake `HealthDataReading`
//  and returns mapped domain objects. No HealthKit import anywhere in this
//  file — the real `HKHealthStore`-backed reader lives in the iOS target and
//  is exercised on-device, per the same split as `HealthKitAuthorizing`.
//

import XCTest
@testable import SpottersaurusKit

/// Test double recording nothing but returning canned data — no HealthKit.
private struct FakeHealthDataReader: HealthDataReading {
    var workouts: [ImportedWorkout]
    var bodyWeight: ImportedBodyWeight?

    func recentWorkouts(limit: Int) async throws -> [ImportedWorkout] {
        Array(workouts.prefix(limit))
    }

    func latestBodyWeight() async throws -> ImportedBodyWeight? {
        bodyWeight
    }
}

private struct ThrowingHealthDataReader: HealthDataReading {
    struct Failure: Error {}

    func recentWorkouts(limit: Int) async throws -> [ImportedWorkout] {
        throw Failure()
    }

    func latestBodyWeight() async throws -> ImportedBodyWeight? {
        throw Failure()
    }
}

final class HealthImporterTests: XCTestCase {

    // MARK: pure mapping

    func testMapCollapsesDuplicateWorkoutsByHealthKitUUID() {
        let sharedUUID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let workouts = [
            ImportedWorkout(healthKitUUID: sharedUUID, activity: .functionalStrengthTraining, start: start, end: end, totalEnergyKcal: 210),
            // Same HK UUID re-delivered (e.g. overlapping query windows).
            ImportedWorkout(healthKitUUID: sharedUUID, activity: .functionalStrengthTraining, start: start, end: end, totalEnergyKcal: 210),
        ]

        let mapped = HealthWorkoutMapper.map(workouts)

        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped.first?.healthKitWorkoutUUID, sharedUUID)
    }

    func testMapCollapsesDuplicatesByStartDateWhenHealthKitUUIDMissing() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let workouts = [
            ImportedWorkout(healthKitUUID: nil, activity: .functionalStrengthTraining, start: start, end: end),
            ImportedWorkout(healthKitUUID: nil, activity: .functionalStrengthTraining, start: start, end: end),
        ]

        let mapped = HealthWorkoutMapper.map(workouts)

        XCTAssertEqual(mapped.count, 1)
    }

    func testMapKeepsDistinctWorkoutsWithDifferentStartDates() {
        let start1 = Date(timeIntervalSince1970: 1_700_000_000)
        let start2 = Date(timeIntervalSince1970: 1_700_100_000)
        let workouts = [
            ImportedWorkout(healthKitUUID: nil, activity: .functionalStrengthTraining, start: start1, end: start1.addingTimeInterval(1800)),
            ImportedWorkout(healthKitUUID: nil, activity: .functionalStrengthTraining, start: start2, end: start2.addingTimeInterval(1800)),
        ]

        let mapped = HealthWorkoutMapper.map(workouts)

        XCTAssertEqual(mapped.count, 2)
    }

    func testMapExcludesNonFunctionalStrengthWorkouts() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workouts = [
            ImportedWorkout(healthKitUUID: UUID(), activity: .functionalStrengthTraining, start: start, end: start.addingTimeInterval(1800)),
            ImportedWorkout(healthKitUUID: UUID(), activity: .running, start: start, end: start.addingTimeInterval(1800)),
            ImportedWorkout(healthKitUUID: UUID(), activity: .other, start: start, end: start.addingTimeInterval(1800)),
        ]

        let mapped = HealthWorkoutMapper.map(workouts)

        XCTAssertEqual(mapped.count, 1)
    }

    func testMapPreservesFieldsForAFunctionalStrengthWorkout() {
        let uuid = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(2400)
        let workouts = [
            ImportedWorkout(healthKitUUID: uuid, activity: .functionalStrengthTraining, start: start, end: end, totalEnergyKcal: 305.5),
        ]

        let mapped = HealthWorkoutMapper.map(workouts)

        let session = try? XCTUnwrap(mapped.first)
        XCTAssertEqual(session?.healthKitWorkoutUUID, uuid)
        XCTAssertEqual(session?.date, start)
        XCTAssertEqual(session?.endDate, end)
        XCTAssertEqual(session?.totalEnergyKcal, 305.5)
    }

    func testMapReturnsEmptyForEmptyInput() {
        XCTAssertEqual(HealthWorkoutMapper.map([]), [])
    }

    // MARK: HealthImporter (read -> map)

    func testHealthImporterReturnsMappedWorkoutsAndBodyWeight() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = FakeHealthDataReader(
            workouts: [
                ImportedWorkout(healthKitUUID: UUID(), activity: .functionalStrengthTraining, start: start, end: start.addingTimeInterval(1800)),
                ImportedWorkout(healthKitUUID: UUID(), activity: .running, start: start, end: start.addingTimeInterval(1800)),
            ],
            bodyWeight: ImportedBodyWeight(date: start, kilograms: 82.3)
        )
        let importer = HealthImporter(reader: reader)

        let result = try await importer.importRecent()

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.bodyWeight?.kilograms, 82.3)
    }

    func testHealthImporterReturnsNilBodyWeightWhenAbsent() async throws {
        let reader = FakeHealthDataReader(workouts: [], bodyWeight: nil)
        let importer = HealthImporter(reader: reader)

        let result = try await importer.importRecent()

        XCTAssertEqual(result.workouts.count, 0)
        XCTAssertNil(result.bodyWeight)
    }

    func testHealthImporterRespectsLimit() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = FakeHealthDataReader(
            workouts: (0..<5).map { offset in
                let day = start.addingTimeInterval(TimeInterval(offset) * 86_400)
                return ImportedWorkout(healthKitUUID: UUID(), activity: .functionalStrengthTraining, start: day, end: day.addingTimeInterval(1800))
            },
            bodyWeight: nil
        )
        let importer = HealthImporter(reader: reader)

        let result = try await importer.importRecent(limit: 2)

        XCTAssertEqual(result.workouts.count, 2)
    }

    func testHealthImporterPropagatesReaderFailure() async {
        let importer = HealthImporter(reader: ThrowingHealthDataReader())

        do {
            _ = try await importer.importRecent()
            XCTFail("expected the reader's throw to propagate")
        } catch {
            XCTAssertTrue(error is ThrowingHealthDataReader.Failure)
        }
    }
}
