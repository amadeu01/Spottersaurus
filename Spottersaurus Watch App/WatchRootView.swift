//
//  WatchRootView.swift
//  Spottersaurus Watch App
//
//  Placeholder root view. Confirms the Watch target links SpottersaurusKit
//  by reading a shared design token + lift label. Real live-set UI is Phase 5.
//

import SwiftUI
import SpottersaurusKit

struct WatchRootView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(Theme.Colors.optimal)
            Text("Spottersaurus")
                .font(.headline)
            Text("\(LiftKind.allCases.count) lifts ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    WatchRootView()
}
