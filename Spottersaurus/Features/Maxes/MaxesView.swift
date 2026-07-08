import SwiftData
import SwiftUI
import SpottersaurusKit

struct MaxesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var maxes: [UserMaxes]

    private let viewModel = MaxesViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Training Maxes") {
                    ForEach(viewModel.competitionMaxes(from: maxes)) { maxRecord in
                        MaxesRow(maxes: maxRecord)
                    }
                }
            }
            .navigationTitle("Maxes")
            .onAppear {
                viewModel.ensureCompetitionMaxesExist(in: modelContext, existingMaxes: maxes)
            }
        }
    }
}

private struct MaxesRow: View {
    @Bindable var maxes: UserMaxes

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(maxes.lift.displayName)
                .font(.system(.headline, design: .rounded, weight: .bold))

            Stepper(value: $maxes.trainingMaxKg, in: 0...500, step: 2.5) {
                MetricLine(label: "Training Max", value: maxes.trainingMaxKg)
            }

            Stepper(value: $maxes.oneRepMaxKg, in: 0...600, step: 2.5) {
                MetricLine(label: "1RM", value: maxes.oneRepMaxKg)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
