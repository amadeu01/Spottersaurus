//
//  Progression.swift
//  SpottersaurusKit
//
//  The pure program-progression engine: computes next-cycle prescriptions
//  and training-max bumps for the two seed presets (`fivethreeone`, `linear`)
//  and resolves a `PlannedSet`'s `%1RM` load against `UserMaxes`. Plain
//  functions over `Double`/`LiftKind` — no SwiftUI, no SwiftData, no I/O.
//
//  Rounding rule: nearest multiple of the barbell increment, ties rounding
//  away from zero (i.e. up for positive weights). This matches plate math —
//  you cannot load a half-increment — and matches the existing
//  `Program.roundToPlate` helper used by the preset builders.
//

import Foundation

/// Namespace for the pure progression engine. All members are stateless
/// functions over value types; safe to call from any actor/thread.
public enum Progression: Sendable {

    /// Round `kg` to the nearest multiple of `increment`, ties away from
    /// zero. `increment <= 0` returns `kg` unchanged (nothing to round to).
    public static func round(_ kg: Double, to increment: Double) -> Double {
        guard increment > 0 else { return kg }
        return (kg / increment).rounded() * increment
    }

    // MARK: - %1RM resolution

    /// The barbell increment used to round resolved weights when the caller
    /// does not supply one explicitly.
    public static let defaultIncrementKg: Double = 2.5

    /// Resolve a `PlannedSet.LoadPrescription.percentOfTrainingMax`-style
    /// percentage against a lifter's one-rep max, rounded to `increment`.
    /// `percent` is a whole-percent value (e.g. `80` means 80%).
    public static func resolvedWeightKg(
        percent: Double,
        oneRepMaxKg: Double,
        increment: Double = defaultIncrementKg
    ) -> Double {
        round(oneRepMaxKg * percent / 100.0, to: increment)
    }

    /// Resolve a `PlannedSet`'s load to an absolute bar weight, rounded to
    /// `increment`. `.absolute` loads are rounded as-is; `.percentOfTrainingMax`
    /// loads scale the training max looked up from `maxes` for the set's
    /// exercise's `LiftKind` (falling back to `0` if the lifter has not set
    /// one yet, matching `Program`'s preset builders).
    public static func resolvedWeightKg(
        for plannedSet: PlannedSet,
        maxes: [UserMaxes],
        increment: Double = defaultIncrementKg
    ) -> Double {
        let trainingMaxKg = plannedSet.exercise.flatMap { exercise in
            maxes.first { $0.lift == exercise.kind }
        }?.trainingMaxKg ?? 0
        return round(plannedSet.resolvedWeightKg(trainingMaxKg: trainingMaxKg), to: increment)
    }
}
