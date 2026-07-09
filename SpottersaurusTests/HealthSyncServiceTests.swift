//
//  HealthSyncServiceTests.swift
//  SpottersaurusTests
//
//  TDD for H3: `HealthSyncService` ties H1 (auth) + H2 (import) together and
//  persists idempotently via `HealthSyncPersister`. No HealthKit anywhere in
//  this file — fakes conform to the package's platform-neutral
//  `HealthKitAuthorizing`/`HealthDataReading` protocols, matching the
//  existing `FakeHealthKitAuthorizer`/`FakeHealthDataReader` pattern from the
//  package's C1/H2 tests.
//

import Foundation
import Testing
import SwiftData
import SpottersaurusKit
@testable import Spottersaurus

private struct TestFailure: Error {}

private actor FakeAuthorizer: HealthKitAuthorizing {
    private(set) var requestCount = 0
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func requestAuthorization() async throws {
        requestCount += 1
        if shouldThrow { throw TestFailure() }
    }

    func authorizationStatusForHeartRate() async -> HealthAuthorizationStatus {
        .sharingAuthorized
    }

    var hasRequestedAuthorization: Bool { requestCount > 0 }
}

private struct FakeReader: HealthDataReading {
    var workouts: [ImportedWorkout] = []
    var bodyWeight: ImportedBodyWeight?
    var shouldThrow = false

    func recentWorkouts(limit: Int) async throws -> [ImportedWorkout] {
        if shouldThrow { throw TestFailure() }
        return workouts
    }

    func latestBodyWeight() async throws -> ImportedBodyWeight? {
        if shouldThrow { throw TestFailure() }
        return bodyWeight
    }
}

/// A reader whose `recentWorkouts` suspends until the test calls `resume()`,
/// so the idle -> syncing -> synced status transition can be observed
/// deterministically instead of racing real async timing.
private actor GatedReader: HealthDataReading {
    private var continuation: CheckedContinuation<Void, Never>?
    private let workouts: [ImportedWorkout]

    init(workouts: [ImportedWorkout]) {
        self.workouts = workouts
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    func recentWorkouts(limit: Int) async throws -> [ImportedWorkout] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return workouts
    }

    func latestBodyWeight() async throws -> ImportedBodyWeight? {
        nil
    }
}

@MainActor
struct HealthSyncServiceTests {

    private func makeContext() throws -> ModelContext {
        let container = try makeModelContainer(inMemory: true, cloudKit: false)
        return ModelContext(container)
    }

    @Test func syncPersistsImportedWorkoutsAndBodyWeight() async throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = FakeReader(
            workouts: [
                ImportedWorkout(healthKitUUID: UUID(), activity: .functionalStrengthTraining, start: start, end: start.addingTimeInterval(1800)),
            ],
            bodyWeight: ImportedBodyWeight(date: start, kilograms: 82.5)
        )
        let service = HealthSyncService(authorizer: FakeAuthorizer(), reader: reader, defaults: UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!)

        await service.sync(context: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.source == .appleHealth)
        #expect(sessions.first?.completedSets?.isEmpty ?? true)

        let weights = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        #expect(weights.count == 1)
        #expect(weights.first?.kilograms == 82.5)
    }

    @Test func secondSyncWithSameDataDoesNotDuplicate() async throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let uuid = UUID()
        let reader = FakeReader(
            workouts: [
                ImportedWorkout(healthKitUUID: uuid, activity: .functionalStrengthTraining, start: start, end: start.addingTimeInterval(1800)),
            ],
            bodyWeight: ImportedBodyWeight(date: start, kilograms: 80)
        )
        let service = HealthSyncService(authorizer: FakeAuthorizer(), reader: reader, defaults: UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!)

        await service.sync(context: context)
        await service.sync(context: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.healthKitWorkoutUUID == uuid)

        let weights = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        #expect(weights.count == 1)
    }

    @Test func bodyWeightUpsertUpdatesLatestValueInPlace() async throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let defaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!

        let firstReader = FakeReader(bodyWeight: ImportedBodyWeight(date: start, kilograms: 80))
        let service = HealthSyncService(authorizer: FakeAuthorizer(), reader: firstReader, defaults: defaults)
        await service.sync(context: context)

        let secondReader = FakeReader(bodyWeight: ImportedBodyWeight(date: start.addingTimeInterval(86_400), kilograms: 81.4))
        let secondService = HealthSyncService(authorizer: FakeAuthorizer(), reader: secondReader, defaults: defaults)
        await secondService.sync(context: context)

        let weights = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        #expect(weights.count == 1)
        #expect(weights.first?.kilograms == 81.4)
    }

    @Test func statusTransitionsIdleToSyncingToSynced() async throws {
        let context = try makeContext()
        let reader = GatedReader(workouts: [])
        let service = HealthSyncService(authorizer: FakeAuthorizer(), reader: reader, defaults: UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!)
        #expect(service.status == .idle)
        #expect(service.lastSyncedAt == nil)

        let syncTask = Task { await service.sync(context: context) }

        var iterations = 0
        while service.status == .idle && iterations < 1000 {
            await Task.yield()
            iterations += 1
        }
        #expect(service.status == .syncing)

        await reader.resume()
        await syncTask.value

        guard case .synced(let syncedDate) = service.status else {
            Issue.record("expected .synced status, got \(service.status)")
            return
        }
        #expect(service.lastSyncedAt == syncedDate)
    }

    @Test func readerThrowingProducesFailedStatusWithNoPartialPersistence() async throws {
        let context = try makeContext()
        let reader = FakeReader(shouldThrow: true)
        let service = HealthSyncService(authorizer: FakeAuthorizer(), reader: reader, defaults: UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!)

        await service.sync(context: context)

        guard case .failed = service.status else {
            Issue.record("expected .failed status, got \(service.status)")
            return
        }
        #expect(service.lastSyncedAt == nil)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.isEmpty)
        let weights = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        #expect(weights.isEmpty)
    }
}
