import Foundation
import SwiftUI

struct ProgramDayBuilderViewModel {
    func addSet(to day: inout ProgramDayDraft) {
        day.sets.append(PlannedSetDraft())
    }

    func deleteSets(at offsets: IndexSet, from day: inout ProgramDayDraft) {
        day.sets.remove(atOffsets: offsets)
    }

    func moveSets(from source: IndexSet, to destination: Int, in day: inout ProgramDayDraft) {
        day.sets.move(fromOffsets: source, toOffset: destination)
    }
}
