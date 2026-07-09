//
//  HealthDataReading.swift
//  SpottersaurusKit
//
//  H2: read recent workouts + latest body weight from Apple Health and map
//  them into the app's domain, idempotently. Split the same way as
//  `HealthKitAuthorizing` (C1/H1): HealthKit-neutral value types + a query
//  protocol live here (testable headless on macOS, where `swift test` runs);
//  the concrete `HKHealthStore`-backed conformer lives in the iOS target
//  (`Spottersaurus/Features/Health/PhoneHealthDataReader.swift`) and is
//  exercised on-device.
//
//  This module reads only — no HealthKit writes, and no persistence. It hands
//  back mapped value types for H3's sync service to persist into SwiftData.
//

import Foundation

/// The workout activity kinds the mapper cares about, mirrored from
/// `HKWorkoutActivityType` without importing HealthKit. The real reader is
/// free to fetch broadly (or filter at the query level); the mapper is the
/// source of truth for "is this a lift we log," which keeps that decision
/// unit-testable without HealthKit.
public enum ImportedWorkoutActivity: Sendable, Equatable {
    case functionalStrengthTraining
    case traditionalStrengthTraining
    case running
    case other
}

/// A HealthKit-neutral snapshot of an `HKWorkout`. No HealthKit types appear
/// here so this is constructible and comparable in package unit tests.
public struct ImportedWorkout: Sendable, Equatable {
    /// The `HKWorkout.uuid`, when the reader can supply one. Nil only in
    /// synthetic/test data — real HealthKit workouts always have a UUID.
    public var healthKitUUID: UUID?
    public var activity: ImportedWorkoutActivity
    public var start: Date
    public var end: Date
    /// Total active energy burned, if the workout recorded it.
    public var totalEnergyKcal: Double?

    public init(
        healthKitUUID: UUID?,
        activity: ImportedWorkoutActivity,
        start: Date,
        end: Date,
        totalEnergyKcal: Double? = nil
    ) {
        self.healthKitUUID = healthKitUUID
        self.activity = activity
        self.start = start
        self.end = end
        self.totalEnergyKcal = totalEnergyKcal
    }

    /// Stable key for in-batch dedupe: the HealthKit UUID when present,
    /// else an ISO8601 rendering of the start date. HealthKit query results
    /// can repeat across overlapping fetch windows/pagination; this collapses
    /// those before anything is handed to a persistence layer.
    var dedupeKey: String {
        healthKitUUID?.uuidString ?? ISO8601DateFormatter().string(from: start)
    }
}

/// A HealthKit-neutral latest body-weight reading, already converted to
/// kilograms by the reader (unit conversion is HealthKit-specific and lives
/// in the concrete reader, not here).
public struct ImportedBodyWeight: Sendable, Equatable {
    public var date: Date
    public var kilograms: Double

    public init(date: Date, kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
    }
}

/// Abstracts the HealthKit queries `HealthImporter` needs, so the pure
/// mapping is testable with a fake and no `HKHealthStore`.
public protocol HealthDataReading: Sendable {
    /// Most recent workouts, newest first, up to `limit`. Implementations may
    /// pre-filter to relevant activity types, but callers must not assume
    /// filtering happened — `HealthWorkoutMapper` re-asserts it.
    func recentWorkouts(limit: Int) async throws -> [ImportedWorkout]

    /// The single most recent body-weight sample, or nil if Health has none /
    /// isn't authorized.
    func latestBodyWeight() async throws -> ImportedBodyWeight?
}

/// The mapped domain record for a functional-strength-training workout,
/// shaped to match `WorkoutSession`'s HealthKit-facing fields
/// (`date`/`healthKitWorkoutUUID`) so H3 can construct one directly:
/// `WorkoutSession(date: mapped.date, source: .phone,
/// healthKitWorkoutUUID: mapped.healthKitWorkoutUUID)`. Deliberately a plain
/// value type rather than the `@Model` itself — Health imports carry no
/// reps/weight/velocity, so there is no `CompletedSet` to attach yet, and
/// keeping this HealthKit- and SwiftData-free keeps the mapping trivially
/// testable.
public struct ImportedWorkoutSession: Sendable, Equatable {
    public var healthKitWorkoutUUID: UUID?
    public var date: Date
    public var endDate: Date
    public var totalEnergyKcal: Double?

    public init(healthKitWorkoutUUID: UUID?, date: Date, endDate: Date, totalEnergyKcal: Double? = nil) {
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.date = date
        self.endDate = endDate
        self.totalEnergyKcal = totalEnergyKcal
    }
}

/// The pure HealthKit -> domain mapping. No I/O, no HealthKit, no SwiftData —
/// takes `ImportedWorkout`s in, returns `ImportedWorkoutSession`s out. This is
/// the primary TDD target for H2.
public enum HealthWorkoutMapper {
    /// Filters to functional-strength-training workouts (the only kind
    /// Spottersaurus logs) and collapses duplicates sharing a `dedupeKey`,
    /// preserving first-seen order.
    public static func map(_ workouts: [ImportedWorkout]) -> [ImportedWorkoutSession] {
        var seenKeys = Set<String>()
        var mapped: [ImportedWorkoutSession] = []
        for workout in workouts {
            guard workout.activity == .functionalStrengthTraining else { continue }
            guard seenKeys.insert(workout.dedupeKey).inserted else { continue }
            mapped.append(
                ImportedWorkoutSession(
                    healthKitWorkoutUUID: workout.healthKitUUID,
                    date: workout.start,
                    endDate: workout.end,
                    totalEnergyKcal: workout.totalEnergyKcal
                )
            )
        }
        return mapped
    }
}

/// The mapped result of a single import pass: functional-strength workouts
/// ready for H3 to persist, plus the latest body weight (if Health has one).
public struct HealthImportResult: Sendable, Equatable {
    public var workouts: [ImportedWorkoutSession]
    public var bodyWeight: ImportedBodyWeight?

    public init(workouts: [ImportedWorkoutSession], bodyWeight: ImportedBodyWeight?) {
        self.workouts = workouts
        self.bodyWeight = bodyWeight
    }
}

/// Reads via an injected `HealthDataReading` and maps through
/// `HealthWorkoutMapper`. Does no persistence — H3's sync service takes this
/// result and writes it into SwiftData, stamping `lastSyncedAt`.
public struct HealthImporter: Sendable {
    private let reader: any HealthDataReading

    public init(reader: any HealthDataReading) {
        self.reader = reader
    }

    /// Reads recent workouts + latest body weight concurrently, then maps the
    /// workouts through the pure mapper. Propagates the reader's errors as-is.
    public func importRecent(limit: Int = 20) async throws -> HealthImportResult {
        async let rawWorkouts = reader.recentWorkouts(limit: limit)
        async let bodyWeight = reader.latestBodyWeight()
        let (workouts, weight) = try await (rawWorkouts, bodyWeight)
        return HealthImportResult(workouts: HealthWorkoutMapper.map(workouts), bodyWeight: weight)
    }
}
