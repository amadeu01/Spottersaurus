import SwiftUI
import SpottersaurusKit

struct ProgramDayBuilderView: View {
    @Binding var day: ProgramDayDraft
    @State private var viewModel = ProgramDayBuilderViewModel()

    var body: some View {
        Form {
            Section("Program Day") {
                TextField("Name", text: $day.name)
            }

            Section("Planned Sets") {
                ForEach($day.sets) { $set in
                    NavigationLink {
                        PlannedSetBuilderView(set: $set)
                    } label: {
                        PlannedSetDraftRow(set: set)
                    }
                }
                .onDelete { viewModel.deleteSets(at: $0, from: &day) }
                .onMove { viewModel.moveSets(from: $0, to: $1, in: &day) }

                Button {
                    viewModel.addSet(to: &day)
                } label: {
                    Label("Add Set", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle(day.name.isEmpty ? "Program Day" : day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                EditButton()
            }
        }
    }
}

private struct PlannedSetDraftRow: View {
    var set: PlannedSetDraft

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(set.exerciseName)
                    .font(.system(.body, design: .rounded, weight: .bold))
                Text(set.load.summary)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(set.isAMRAP ? "\(set.targetReps)+" : "\(set.targetReps)")
                .font(.system(.body, design: .rounded, weight: .heavy))
                .monospacedDigit()
        }
    }
}

#Preview {
    @Previewable @State var day = ProgramDayDraft(
        name: "Squat Day",
        sets: [
            PlannedSetDraft(lift: .squat, targetReps: 5, load: PlannedSetLoadDraft(kind: .percentOfTrainingMax, value: 85)),
            PlannedSetDraft(lift: .accessory, targetReps: 12, load: PlannedSetLoadDraft(kind: .absolute, value: 40)),
        ]
    )

    return NavigationStack {
        ProgramDayBuilderView(day: $day)
    }
}
