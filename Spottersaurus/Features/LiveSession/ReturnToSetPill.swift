//
//  ReturnToSetPill.swift
//  Spottersaurus
//
//  Small persistent affordance shown app-wide (over any tab) after the
//  lifter manually dismisses the In-Workout View (S1) while its Live Session
//  is still running — tapping it reopens the full-screen takeover.
//  Session-scoped: `ContentView` only shows this while `LiveSessionMonitor`
//  reports an armed/active/resting phase.
//

import SwiftUI
import SpottersaurusKit

struct ReturnToSetPill: View {
    var setLabel: String
    var alertStage: AlertStage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbolName)
                    .font(.system(.body, weight: .bold))

                Text(setLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.up")
                    .font(.system(.caption, weight: .bold))
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 44)
            .foregroundStyle(.white)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Return to live set: \(setLabel)")
    }

    private var symbolName: String {
        switch alertStage {
        case .none: "figure.strengthtraining.traditional"
        case .grinding: "exclamationmark.triangle.fill"
        case .rackIt: "hand.raised.fill"
        }
    }

    private var tint: Color {
        switch alertStage {
        case .none: Theme.Colors.brandOrange
        case .grinding: Theme.Colors.caution
        case .rackIt: Theme.Colors.alert
        }
    }
}

#Preview("All states") {
    ZStack {
        Theme.Colors.canvas.ignoresSafeArea()
        VStack(spacing: Theme.Spacing.md) {
            ReturnToSetPill(setLabel: "Set 2 of 4 · Bench Press", alertStage: .none) {}
            ReturnToSetPill(setLabel: "Set 3 of 4 · Squat", alertStage: .grinding) {}
            ReturnToSetPill(setLabel: "Set 3 of 4 · Squat", alertStage: .rackIt) {}
        }
        .padding()
    }
}
