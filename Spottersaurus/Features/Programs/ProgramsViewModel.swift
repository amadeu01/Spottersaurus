import Foundation
import SwiftData
import SpottersaurusKit

struct ProgramsViewModel {
    func sortedPrograms(_ programs: [Program]) -> [Program] {
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

    func deletePrograms(at offsets: IndexSet, from programs: [Program], in modelContext: ModelContext) {
        let sorted = sortedPrograms(programs)
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}
