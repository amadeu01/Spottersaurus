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

        Section {
            LabeledContent("Mesocycle") {
                TextField("Optional", text: optionalIntBinding(for: $draft.mesocycleNumber))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Week") {
                TextField("Optional", text: optionalIntBinding(for: $draft.weekNumber))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Mesocycle / Week")
        } footer: {
            Text("Optional — labels a program pasted or copied from a coach-authored block. Leave blank if this program doesn't belong to a numbered week.")
        }
    }

    /// Bridges an `Int?` binding to a `String` `TextField`, mapping a blank
    /// string to `nil` and a non-numeric entry to the prior value.
    private func optionalIntBinding(for value: Binding<Int?>) -> Binding<String> {
        Binding<String>(
            get: {
                value.wrappedValue.map(String.init) ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    value.wrappedValue = nil
                } else if let parsed = Int(trimmed) {
                    value.wrappedValue = parsed
                }
                // Non-numeric input is ignored, leaving the prior value intact.
            }
        )
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

#Preview {
    ProgramBuilderView { _ in }
}
