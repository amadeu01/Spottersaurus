import SwiftUI
import SpottersaurusKit

struct ProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProgramBuilderViewModel()

    var onSave: (ProgramDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                ProgramMetadataSection(draft: $viewModel.draft)

                Section("Program Days") {
                    ForEach($viewModel.draft.days) { $day in
                        NavigationLink {
                            ProgramDayBuilderView(day: $day)
                        } label: {
                            ProgramDayDraftRow(day: day)
                        }
                    }
                    .onDelete { viewModel.deleteDays(at: $0) }
                    .onMove { viewModel.moveDays(from: $0, to: $1) }

                    Button {
                        viewModel.addDay()
                    } label: {
                        Label("Add Day", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onSave(viewModel.normalizedDraft())
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }

                ToolbarItem(placement: .bottomBar) {
                    EditButton()
                }
            }
        }
    }
}

private struct ProgramMetadataSection: View {
    @Binding var draft: ProgramDraft

    var body: some View {
        Section("Program") {
            TextField("Name", text: $draft.name)

            Picker("Progression", selection: $draft.rule) {
                ForEach(ProgressionRule.allCases) { rule in
                    Text(rule.displayName).tag(rule)
                }
            }
        }
    }
}

private struct ProgramDayDraftRow: View {
    var day: ProgramDayDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(day.name)
                .font(.system(.body, design: .rounded, weight: .bold))
            Text("\(day.sets.count) planned sets")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
