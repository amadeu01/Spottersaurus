import Foundation
import Observation
import SpottersaurusKit

/// Owns the derived analytics input the Analytics charts render. `AnalyticsView`
/// keeps a lightweight `@Query` for CloudKit/SwiftData reactivity and pipes
/// results in via `update(with:)` on change — the same hybrid pattern
/// `HistoryViewModel` (F1) uses. The pure `PerformanceAnalytics` layer still
/// does all the math; this type only owns the mapped `SetRecord` inputs.
@MainActor
@Observable
final class AnalyticsViewModel {
    /// The `SetRecord`s derived from the last `update(with:)` call. Set only
    /// via `update(with:)`.
    private(set) var records: [SetRecord] = []

    /// Replaces the derived `SetRecord` inputs with a fresh mapping of
    /// `sessions`. Call this from `@Query`'s `.onChange` (with an initial
    /// load) so the owned state tracks live SwiftData/CloudKit updates.
    func update(with sessions: [WorkoutSession]) {
        records = Self.records(from: sessions)
    }

    private static func records(from sessions: [WorkoutSession]) -> [SetRecord] {
        sessions.flatMap { session in
            (session.completedSets ?? []).compactMap { set in
                guard let lift = set.exercise?.kind else { return nil }
                return SetRecord(
                    lift: lift,
                    date: set.startedAt,
                    weightKg: set.weightKg,
                    reps: set.repsPerformed,
                    meanConcentricVelocityMS: set.avgConcentricVelocityMS > 0 ? set.avgConcentricVelocityMS : nil,
                    spotterEvents: set.spotterEvents
                )
            }
        }
    }

    func e1RMTrend(lift: LiftKind) -> [PerformanceAnalytics.TrendPoint] {
        PerformanceAnalytics.e1RMTrend(for: records, lift: lift)
    }

    func tonnageSeries(lift: LiftKind) -> [PerformanceAnalytics.TonnagePoint] {
        PerformanceAnalytics.tonnageSeries(for: records, lift: lift)
    }

    func velocityLoadPoints(lift: LiftKind) -> [PerformanceAnalytics.VelocityLoadPoint] {
        PerformanceAnalytics.velocityLoadPoints(for: records, lift: lift)
    }

    func spotterFrequency(lift: LiftKind?) -> PerformanceAnalytics.SpotterEventFrequency {
        PerformanceAnalytics.spotterEventFrequency(for: records, lift: lift)
    }

    func totalTonnage() -> String {
        PerformanceAnalytics.tonnage(for: records).formatted(.number.precision(.fractionLength(0)))
    }

    func bestEstimatedOneRepMax(lift: LiftKind) -> String {
        let best = records
            .filter { $0.lift == lift }
            .map { PerformanceAnalytics.e1RM(for: $0) }
            .max() ?? 0
        return best.formatted(.number.precision(.fractionLength(1)))
    }
}
