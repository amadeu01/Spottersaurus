import Foundation
import SpottersaurusKit

struct AnalyticsViewModel {
    func records(from sessions: [WorkoutSession]) -> [SetRecord] {
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

    func e1RMTrend(from records: [SetRecord], lift: LiftKind) -> [PerformanceAnalytics.TrendPoint] {
        PerformanceAnalytics.e1RMTrend(for: records, lift: lift)
    }

    func tonnageSeries(from records: [SetRecord], lift: LiftKind) -> [PerformanceAnalytics.TonnagePoint] {
        PerformanceAnalytics.tonnageSeries(for: records, lift: lift)
    }

    func velocityLoadPoints(from records: [SetRecord], lift: LiftKind) -> [PerformanceAnalytics.VelocityLoadPoint] {
        PerformanceAnalytics.velocityLoadPoints(for: records, lift: lift)
    }

    func spotterFrequency(from records: [SetRecord], lift: LiftKind?) -> PerformanceAnalytics.SpotterEventFrequency {
        PerformanceAnalytics.spotterEventFrequency(for: records, lift: lift)
    }

    func totalTonnage(from records: [SetRecord]) -> String {
        PerformanceAnalytics.tonnage(for: records).formatted(.number.precision(.fractionLength(0)))
    }

    func bestEstimatedOneRepMax(from records: [SetRecord], lift: LiftKind) -> String {
        let best = records
            .filter { $0.lift == lift }
            .map { PerformanceAnalytics.e1RM(for: $0) }
            .max() ?? 0
        return best.formatted(.number.precision(.fractionLength(1)))
    }
}
