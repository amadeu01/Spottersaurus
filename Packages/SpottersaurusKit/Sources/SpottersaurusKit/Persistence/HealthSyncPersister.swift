//
//  HealthSyncPersister.swift
//  SpottersaurusKit
//
//  H3: persists a `HealthImportResult` (H2's read+map output) into SwiftData,
//  idempotently. Mirrors `SessionImporter`'s upsert-by-id shape, but keyed on
//  `healthKitWorkoutUUID` (Health's stable identity for a workout) rather than
//  an envelope id, and — since Health imports carry no reps/weight/velocity —
//  writes only a lightweight history placeholder: date + `.appleHealth`
//  source marker, no fabricated `CompletedSet`s. Body weight is a single
//  upserted `BodyWeightEntry` row (H3 keeps only "the latest" value, not a
//  full history — see that model's doc comment).
//
//  Pure w.r.t. transport: no HealthKit, no networking. The caller (H3's
//  `HealthSyncService`, in the iOS target) owns the `ModelContext` lifecycle.
//

import Foundation
import SwiftData

@MainActor
public enum HealthSyncPersister {

    /// Persists every imported workout (upsert by `healthKitWorkoutUUID`) and
    /// the latest body weight (if present), then saves `context` once.
    ///
    /// - Returns: the inserted/updated `WorkoutSession`s, in the same order as
    ///   `result.workouts`.
    @discardableResult
    public static func persist(_ result: HealthImportResult, into context: ModelContext) throws -> [WorkoutSession] {
        let sessions = try result.workouts.map { try upsertWorkoutSession($0, context: context) }
        if let bodyWeight = result.bodyWeight {
            try upsertBodyWeight(bodyWeight, context: context)
        }
        try context.save()
        return sessions
    }

    /// Upserts a single imported workout by its HealthKit UUID so a re-sync of
    /// the same Health data never duplicates history. Real HealthKit workouts
    /// always carry a UUID (per `ImportedWorkout`'s doc comment) — a nil UUID
    /// only occurs in synthetic/test data, and is treated as always-new since
    /// there is no stable key to upsert against.
    private static func upsertWorkoutSession(_ imported: ImportedWorkoutSession, context: ModelContext) throws -> WorkoutSession {
        if let uuid = imported.healthKitWorkoutUUID {
            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.healthKitWorkoutUUID == uuid }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.date = imported.date
                return existing
            }
        }
        let session = WorkoutSession(
            date: imported.date,
            source: .appleHealth,
            healthKitWorkoutUUID: imported.healthKitWorkoutUUID
        )
        context.insert(session)
        return session
    }

    /// Keeps at most one `BodyWeightEntry` row, updated in place — "the
    /// latest" is all the Profile screen needs (see `BodyWeightEntry`'s doc
    /// comment).
    private static func upsertBodyWeight(_ imported: ImportedBodyWeight, context: ModelContext) throws {
        if let existing = try context.fetch(FetchDescriptor<BodyWeightEntry>()).first {
            existing.date = imported.date
            existing.kilograms = imported.kilograms
        } else {
            context.insert(BodyWeightEntry(date: imported.date, kilograms: imported.kilograms))
        }
    }
}
