//
//  PreviewSeedData.swift
//  Spottersaurus
//
//  Debug-only seed helpers shared across `#Preview`s so the F6 preview sweep
//  doesn't hand-roll domain objects in every file. Kept intentionally small —
//  just enough for a feature view to render non-empty.
//

#if DEBUG
import Foundation
import SwiftData
import SpottersaurusKit

@MainActor
enum PreviewSeed {
    /// One `UserMaxes` per competition lift, in SBD order.
    static func maxes() -> [UserMaxes] {
        [
            UserMaxes(lift: .squat, trainingMaxKg: 180, oneRepMaxKg: 200),
            UserMaxes(lift: .bench, trainingMaxKg: 120, oneRepMaxKg: 135),
            UserMaxes(lift: .deadlift, trainingMaxKg: 220, oneRepMaxKg: 245),
        ]
    }

    /// A 5/3/1 program built from `maxes()`, unattached to any context.
    static func program(maxes: [UserMaxes]) -> Program {
        Program.fiveThreeOne(maxes: maxes)
    }

    /// A single logged bench set with rep metrics and a grind→rack-it escalation,
    /// wrapped in a finished `WorkoutSession`.
    static func workoutSession(date: Date = .now) -> WorkoutSession {
        let session = WorkoutSession(date: date, source: .watch)
        let exercise = Exercise(name: "Bench Press", kind: .bench)
        let set = CompletedSet(
            exercise: exercise,
            weightKg: 100,
            repsPerformed: 5,
            startedAt: date,
            avgConcentricVelocityMS: 0.38,
            peakConcentricVelocityMS: 0.55,
            spotterEvents: [
                SpotterEvent(stage: .grind, timestamp: 14, repIndex: 3),
                SpotterEvent(stage: .rackIt, timestamp: 19, repIndex: 4),
            ]
        )
        for index in 0..<5 {
            set.appendRepMetric(
                RepMetric(
                    repIndex: index,
                    concentricSeconds: 1.1 + Double(index) * 0.15,
                    peakVelocityMS: 0.6 - Double(index) * 0.05,
                    meanVelocityMS: 0.45 - Double(index) * 0.04,
                    romProxy: 0.9,
                    flaggedStall: index >= 3
                )
            )
        }
        session.appendCompletedSet(set)
        return session
    }

    /// Inserts a full seeded graph (maxes, a 5/3/1 program, one finished
    /// session) into `context` — the common case for previews that read via
    /// `@Query`.
    @discardableResult
    static func insertStandardSeed(into context: ModelContext) -> (maxes: [UserMaxes], program: Program, session: WorkoutSession) {
        let seededMaxes = maxes()
        for max in seededMaxes { context.insert(max) }

        let seededProgram = program(maxes: seededMaxes)
        context.insert(seededProgram)

        let seededSession = workoutSession()
        context.insert(seededSession)

        return (seededMaxes, seededProgram, seededSession)
    }

    /// A ready-to-use in-memory container seeded via `insertStandardSeed`.
    static func seededContainer() -> ModelContainer {
        let container = try! makeModelContainer(inMemory: true, cloudKit: false)
        insertStandardSeed(into: container.mainContext)
        return container
    }

    /// A single imported body weight, as `HealthSyncPersister` would upsert it.
    static func bodyWeightEntry(date: Date = .now, kilograms: Double = 82.5) -> BodyWeightEntry {
        BodyWeightEntry(date: date, kilograms: kilograms)
    }

    /// `insertStandardSeed` plus a `bodyWeightEntry()` — the common case for
    /// Profile (P1) previews that render both the Maxes editor and body info.
    static func profileSeededContainer() -> ModelContainer {
        let container = try! makeModelContainer(inMemory: true, cloudKit: false)
        insertStandardSeed(into: container.mainContext)
        container.mainContext.insert(bodyWeightEntry())
        return container
    }
}
#endif
