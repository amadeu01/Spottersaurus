import Foundation
import Observation
import SwiftUI

@Observable
final class ProgramBuilderViewModel {
    var draft = ProgramDraft()

    var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draft.days.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.sets.isEmpty }
    }

    func addDay() {
        draft.days.append(ProgramDayDraft(name: "Day \(draft.days.count + 1)"))
    }

    func deleteDays(at offsets: IndexSet) {
        draft.days.remove(atOffsets: offsets)
    }

    func moveDays(from source: IndexSet, to destination: Int) {
        draft.days.move(fromOffsets: source, toOffset: destination)
    }

    func normalizedDraft() -> ProgramDraft {
        draft.normalized()
    }
}
