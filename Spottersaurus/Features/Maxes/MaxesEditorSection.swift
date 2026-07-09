//
//  MaxesEditorSection.swift
//  Spottersaurus
//
//  P1: the "Training Maxes" editor content extracted out of `MaxesView` so
//  `ProfileView` can embed the exact same SwiftData-backed section (Profile
//  absorbs Maxes in P2). Owns its own `@Query`/`MaxesViewModel` — callers
//  just drop `MaxesEditorSection()` into any `List`.
//

import SwiftData
import SwiftUI
import SpottersaurusKit

struct MaxesEditorSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var maxes: [UserMaxes]

    @State private var viewModel = MaxesViewModel()

    var body: some View {
        Section("Training Maxes") {
            ForEach(viewModel.competitionMaxes) { maxRecord in
                MaxesRow(maxes: maxRecord)
            }
        }
        .onAppear {
            viewModel.ensureCompetitionMaxesExist(in: modelContext, existingMaxes: maxes)
        }
        .onChange(of: maxes, initial: true) { _, newValue in
            viewModel.update(with: newValue)
        }
    }
}

struct MaxesRow: View {
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

#Preview {
    List {
        MaxesEditorSection()
    }
    .modelContainer(PreviewSeed.seededContainer())
}
