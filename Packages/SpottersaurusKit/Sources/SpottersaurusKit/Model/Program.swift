//
//  Program.swift
//  SpottersaurusKit
//
//  A training program: a named, ordered list of days with a progression rule.
//  Owns its days with a cascade delete. Order is explicit via each day's
//  `sortIndex`; `orderedDays` is the sorted view callers should read.
//
//  Also home to the two seed presets — `fiveThreeOne(maxes:)` and
//  `linearProgression(...)` — which build a ready-to-train program from a set
//  of `UserMaxes`. The presets create their own `Exercise` instances; insert
//  the returned graph into a `ModelContext` to persist it.
//

import Foundation
import SwiftData

/// How a program advances load over time.
public enum ProgressionRule: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Wendler 5/3/1 — percentage-of-training-max waves.
    case fivethreeone
    /// Linear progression — add a fixed increment each session.
    case linear
    /// User-authored, no automatic progression.
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fivethreeone: "5/3/1"
        case .linear: "Linear Progression"
        case .custom: "Custom"
        }
    }
}

/// A training program owning an ordered list of `ProgramDay`s.
@Model
public final class Program {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Progression rule; persisted by raw value.
    public var rule: ProgressionRule = ProgressionRule.custom
    public var createdAt: Date = Date()

    /// The program's days. Cascade delete: removing the program removes its
    /// days (and, transitively, their planned sets). Read `orderedDays`.
    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
    public var days: [ProgramDay]?

    /// Sessions logged against this program. Nullify on delete — deleting a
    /// program must not delete logged history.
    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.program)
    public var sessions: [WorkoutSession]?

    public init(name: String, rule: ProgressionRule, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.rule = rule
        self.createdAt = createdAt
    }

    /// Days sorted by their explicit order index.
    public var orderedDays: [ProgramDay] {
        (days ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    public func appendDay(_ day: ProgramDay) {
        var existing = days ?? []
        existing.append(day)
        days = existing
    }
}

// MARK: - Seed presets

public extension Program {

    /// Round a bar weight to the nearest `step` kilograms (default 2.5 kg plate
    /// math). Keeps preset loads gym-realistic and deterministic for tests.
    static func roundToPlate(_ kg: Double, step: Double = 2.5) -> Double {
        guard step > 0 else { return kg }
        return (kg / step).rounded() * step
    }

    /// The three competition lifts, in canonical order. Accessory work is added
    /// by the user in the builder, not by the presets.
    private static var presetLifts: [LiftKind] { [.squat, .bench, .deadlift] }

    /// Look up a training max (kg) for a lift from a maxes collection, falling
    /// back to 0 when the user has not set one yet.
    private static func trainingMax(for lift: LiftKind, in maxes: [UserMaxes]) -> Double {
        maxes.first { $0.lift == lift }?.trainingMaxKg ?? 0
    }

    /// Build a Wendler **5/3/1** preset (the "5s" week) from the supplied maxes.
    /// One day per SBD lift; each day's main work is 65% × 5, 75% × 5, 85% × 5+
    /// (AMRAP) of the lift's training max, expressed as percentage loads so the
    /// program tracks the maxes without re-baking weights.
    static func fiveThreeOne(maxes: [UserMaxes]) -> Program {
        let program = Program(name: "5/3/1", rule: .fivethreeone)
        // Wendler week-1 main set scheme: percent of TM × reps, last AMRAP.
        let scheme: [(percent: Double, reps: Int, amrap: Bool)] = [
            (65, 5, false),
            (75, 5, false),
            (85, 5, true),
        ]
        for (dayIndex, lift) in presetLifts.enumerated() {
            let exercise = Exercise(name: lift.displayName, kind: lift)
            let day = ProgramDay(name: "\(lift.displayName) Day", sortIndex: dayIndex)
            for (setIndex, step) in scheme.enumerated() {
                let set = PlannedSet(
                    exercise: exercise,
                    targetReps: step.reps,
                    load: .percentOfTrainingMax(percent: step.percent),
                    isAMRAP: step.amrap,
                    restSeconds: 180,
                    sortIndex: setIndex
                )
                day.appendPlannedSet(set)
            }
            program.appendDay(day)
        }
        return program
    }

    /// Build a **linear progression** preset from the supplied maxes: one day
    /// per SBD lift, `sets` × `reps` straight sets at a fixed starting load
    /// derived from the lift's training max (`startingFraction`), rounded to the
    /// plate. The fixed `incrementKg` is the per-session bump the progression
    /// engine applies later; it is recorded here as the program's intent.
    static func linearProgression(
        maxes: [UserMaxes],
        sets: Int = 5,
        reps: Int = 5,
        startingFraction: Double = 0.60,
        incrementKg: Double = 2.5
    ) -> Program {
        let program = Program(name: "Linear Progression", rule: .linear)
        for (dayIndex, lift) in presetLifts.enumerated() {
            let exercise = Exercise(name: lift.displayName, kind: lift)
            let day = ProgramDay(name: "\(lift.displayName) Day", sortIndex: dayIndex)
            let tm = trainingMax(for: lift, in: maxes)
            let startWeight = roundToPlate(tm * startingFraction)
            for setIndex in 0..<max(0, sets) {
                let set = PlannedSet(
                    exercise: exercise,
                    targetReps: reps,
                    load: .absolute(kg: startWeight),
                    isAMRAP: false,
                    restSeconds: 180,
                    sortIndex: setIndex
                )
                day.appendPlannedSet(set)
            }
            program.appendDay(day)
        }
        return program
    }
}
