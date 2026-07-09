import Foundation
import Observation
import SwiftData
import SpottersaurusKit

/// Owns the derived (competition-order) `UserMaxes` rows the Maxes editor
/// renders. `MaxesView` keeps a lightweight `@Query` for CloudKit/SwiftData
/// reactivity and pipes results in via `update(with:)` on change — the same
/// hybrid pattern `HistoryViewModel` (F1) / `AnalyticsViewModel` (F2) use.
@MainActor
@Observable
final class MaxesViewModel {
    static let competitionLifts: [LiftKind] = [.squat, .bench, .deadlift]

    /// The competition-lift `UserMaxes` rows, ordered squat → bench →
    /// deadlift. Set only via `update(with:)`.
    private(set) var competitionMaxes: [UserMaxes] = []

    /// Replaces the derived rows with the competition-lift subset of `maxes`,
    /// ordered squat → bench → deadlift. Call this from `@Query`'s
    /// `.onChange` (with an initial load) so the owned state tracks live
    /// SwiftData/CloudKit updates.
    func update(with maxes: [UserMaxes]) {
        competitionMaxes = Self.competitionMaxes(from: maxes)
    }

    private static func competitionMaxes(from maxes: [UserMaxes]) -> [UserMaxes] {
        competitionLifts.compactMap { lift in
            maxes.first { $0.lift == lift }
        }
    }

    /// Inserts a zeroed `UserMaxes` for any competition lift missing from
    /// `existingMaxes`. A side effect on `modelContext`, not derived state —
    /// call before `update(with:)` so the freshly inserted rows are picked up
    /// by the next `@Query` fetch/`.onChange`.
    func ensureCompetitionMaxesExist(in modelContext: ModelContext, existingMaxes: [UserMaxes]) {
        for lift in Self.competitionLifts where !existingMaxes.contains(where: { $0.lift == lift }) {
            modelContext.insert(UserMaxes(lift: lift, trainingMaxKg: 0, oneRepMaxKg: 0))
        }
    }
}
