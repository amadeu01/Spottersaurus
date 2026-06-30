//
//  ContentView.swift
//  Spottersaurus
//
//  Phase 1 placeholder. The iPhone planner/reviewer UI (Today, program
//  builder, history, charts) is built in Phases 7-8.
//

import SwiftUI
import SpottersaurusKit

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.optimal)
                Text("Spottersaurus")
                    .font(.largeTitle.bold())
                Text("Planner & reviewer — coming in later phases.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Spottersaurus")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
