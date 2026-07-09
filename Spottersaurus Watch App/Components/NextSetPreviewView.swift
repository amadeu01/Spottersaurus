//
//  NextSetPreviewView.swift
//  Spottersaurus Watch App
//
//  Shown while resting so the next set's prescription is a one-tap start
//  (Phase 0.2 M1b). Purely informational — the Watch never auto-arms the
//  next set from this preview; a manual Arm tap is always required (see
//  `LiveSetView`'s "manual arm per set" flow / `docs/adr/
//  0001-live-session-surfaces-and-transport.md`).
//

import SwiftUI
import SpottersaurusKit

struct NextSetPreviewView: View {
    var nextSet: PlannedSetEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NEXT")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
            Text(detailText)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(detailText)")
    }

    private var detailText: String {
        let weight = String(format: "%.1f", nextSet.weightKg)
        return "\(nextSet.exerciseName) · \(nextSet.targetReps) reps · \(weight) kg"
    }
}

#Preview {
    NextSetPreviewView(
        nextSet: PlannedSetEnvelope(
            lift: .squat,
            exerciseName: "Back Squat",
            targetReps: 5,
            weightKg: 140,
            restSeconds: 180,
            sortIndex: 1
        )
    )
    .padding()
    .background(Theme.Colors.canvas)
}
