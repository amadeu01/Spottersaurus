import Foundation
import Observation
import SwiftData
import SpottersaurusKit

/// Owns the derived (sorted, newest-first) `Program` list `ProgramsView`
/// renders. `ProgramsView` keeps a lightweight `@Query` for CloudKit/SwiftData
/// reactivity and pipes results in via `update(with:)` on change — the same
/// hybrid pattern `HistoryViewModel` (F1) / `AnalyticsViewModel` (F2) /
/// `MaxesViewModel` (F3) use.
@MainActor
@Observable
final class ProgramsViewModel {
    /// The sorted (newest-first) programs the UI renders. Set only via
    /// `update(with:)`.
    private(set) var programs: [Program] = []

    /// Replaces the derived program list with a freshly sorted copy of
    /// `programs`. Call this from `@Query`'s `.onChange` (with an initial
    /// load) so the owned state tracks live SwiftData/CloudKit updates.
    func update(with programs: [Program]) {
        self.programs = Self.sorted(programs)
    }

    private static func sorted(_ programs: [Program]) -> [Program] {
        programs.sorted { $0.createdAt > $1.createdAt }
    }

    func loadFiveThreeOne(maxes: [UserMaxes], into modelContext: ModelContext) {
        modelContext.insert(Program.fiveThreeOne(maxes: maxes))
    }

    func loadLinearProgression(maxes: [UserMaxes], into modelContext: ModelContext) {
        modelContext.insert(Program.linearProgression(maxes: maxes))
    }

    func createProgram(from draft: ProgramDraft, in modelContext: ModelContext) {
        modelContext.insert(draft.makeProgram())
    }

    /// Deletes the owned (sorted) programs at `offsets`. A side effect on
    /// `modelContext`, not derived state — offsets are expected to index into
    /// `programs`, matching the order `ProgramsView` renders.
    func deletePrograms(at offsets: IndexSet, in modelContext: ModelContext) {
        for index in offsets {
            modelContext.delete(programs[index])
        }
    }
}
