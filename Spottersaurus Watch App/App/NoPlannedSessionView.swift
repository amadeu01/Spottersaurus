//
//  NoPlannedSessionView.swift
//  Spottersaurus Watch App
//
//  Honest empty state when the Watch has never received a
//  `PlannedSessionEnvelope` from the iPhone — replaces the old hardcoded
//  bench @ 100 kg fallback in `WatchPlannedSessionStore.currentPlannedSet()`
//  (Phase 0.2 M1b, the "everything is bench" bug). `WatchRootView` renders
//  this whenever `WatchPlannedSessionStore.shared.cursor == nil`.
//

import SwiftUI
import SpottersaurusKit

struct NoPlannedSessionView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No session")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text("Send today's session from iPhone to begin.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.canvas)
    }
}

#Preview {
    NoPlannedSessionView()
}
