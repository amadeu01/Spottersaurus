//
//  SessionCompleteView.swift
//  Spottersaurus Watch App
//
//  Shown once every set in the day's Live Session has been racked and its
//  rest fully elapsed (`PlannedSessionCursor.isFinished`, Phase 0.2 M1b).
//  Distinct from `NoPlannedSessionView` — a session WAS run, it's just done;
//  the Watch waits here for the iPhone to send the next day's session
//  (which resets the cursor back to set 1 — see
//  `WatchPlannedSessionStore.store(_:)`).
//

import SwiftUI
import SpottersaurusKit

struct SessionCompleteView: View {
    var setCount: Int

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(Theme.Colors.optimal)
            Text("Session complete")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text("\(setCount) set\(setCount == 1 ? "" : "s") done. Nice work.")
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
    SessionCompleteView(setCount: 4)
}
