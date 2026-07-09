import SwiftData
import SwiftUI
import SpottersaurusKit

struct ProgramsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var programs: [Program]
    @Query private var maxes: [UserMaxes]
    @State private var showingBuilder = false

    @State private var viewModel = ProgramsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.loadFiveThreeOne(maxes: maxes, into: modelContext)
                    } label: {
                        Label("Load 5/3/1", systemImage: "plus.circle.fill")
                    }

                    Button {
                        viewModel.loadLinearProgression(maxes: maxes, into: modelContext)
                    } label: {
                        Label("Load Linear", systemImage: "plus.circle.fill")
                    }
                }

                Section("Programs") {
                    ForEach(viewModel.programs) { program in
                        NavigationLink {
                            ProgramDetailView(program: program, maxes: maxes)
                        } label: {
                            ProgramListRow(program: program)
                        }
                    }
                    .onDelete { offsets in
                        viewModel.deletePrograms(at: offsets, in: modelContext)
                    }
                }
            }
            .navigationTitle("Programs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingBuilder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Program")
                }
            }
            .sheet(isPresented: $showingBuilder) {
                ProgramBuilderView { draft in
                    viewModel.createProgram(from: draft, in: modelContext)
                }
            }
            .onChange(of: programs, initial: true) { _, newValue in
                viewModel.update(with: newValue)
            }
        }
    }
}

private struct ProgramListRow: View {
    var program: Program

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(program.name)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text("\(program.rule.displayName) · \(program.orderedDays.count) days")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ProgramsView()
        .modelContainer(PreviewSeed.seededContainer())
}
