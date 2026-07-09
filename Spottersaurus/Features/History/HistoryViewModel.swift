import Foundation
import Observation
import SwiftData
import SpottersaurusKit

/// Owns the derived (sorted) session list History renders. `HistoryView` keeps
/// a lightweight `@Query` for CloudKit/SwiftData reactivity and pipes results
/// in via `update(with:)` on change — the hybrid pattern from the 2026-07-09
/// grill. Pure formatting helpers stay on the type so row/detail views can
/// keep calling them unchanged.
@MainActor
@Observable
final class HistoryViewModel {
    /// The sorted (newest-first) sessions the UI renders. Set only via
    /// `update(with:)`.
    private(set) var sessions: [WorkoutSession] = []

    /// Replaces the derived session list with a freshly sorted copy of
    /// `sessions`. Call this from `@Query`'s `.onChange` (with an initial
    /// load) so the owned state tracks live SwiftData/CloudKit updates.
    func update(with sessions: [WorkoutSession]) {
        self.sessions = Self.sorted(sessions)
    }

    private static func sorted(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.sorted { $0.date > $1.date }
    }

    func orderedSets(in session: WorkoutSession) -> [CompletedSet] {
        (session.completedSets ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    func sessionTitle(_ session: WorkoutSession) -> String {
        session.date.formatted(date: .abbreviated, time: .shortened)
    }

    func sessionSubtitle(_ session: WorkoutSession) -> String {
        let setCount = orderedSets(in: session).count
        let tonnage = session.totalTonnageKg.formatted(.number.precision(.fractionLength(0)))
        return "\(setCount) sets · \(tonnage) kg"
    }

    func setTitle(_ set: CompletedSet) -> String {
        set.exercise?.name ?? set.exercise?.kind.displayName ?? "Lift"
    }

    func setSubtitle(_ set: CompletedSet) -> String {
        let load = set.weightKg.formatted(.number.precision(.fractionLength(1)))
        let e1RM = set.estimatedOneRepMaxKg.formatted(.number.precision(.fractionLength(1)))
        return "\(load) kg × \(set.repsPerformed) · e1RM \(e1RM) kg"
    }

    func velocitySummary(_ set: CompletedSet) -> String {
        let average = set.avgConcentricVelocityMS.formatted(.number.precision(.fractionLength(2)))
        let peak = set.peakConcentricVelocityMS.formatted(.number.precision(.fractionLength(2)))
        return "\(average) avg / \(peak) peak"
    }

    func refreshSavedSessionCount(in modelContext: ModelContext, logger: any AppLogger = LoggerGroup.iPhone) {
        let descriptor = FetchDescriptor<WorkoutSession>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        logger.info(.persistence, "history refresh savedSessionCount=\(count)")
    }
}
