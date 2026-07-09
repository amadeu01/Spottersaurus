//
//  SetPositionBadgeView.swift
//  Spottersaurus Watch App
//
//  Small "Set N of M" pill showing whole-day progression through a Live
//  Session's ordered sets — the piece of context that didn't exist before
//  Phase 0.2 M1b, when the Watch only ever ran the first set of the day.
//  Distinct from `LiveSetHeaderView` (per-set exercise name/status): this is
//  the day-level position, so it's shown alongside the header rather than
//  folded into it.
//

import SwiftUI
import SpottersaurusKit

struct SetPositionBadgeView: View {
    var setIndex: Int
    var setCount: Int

    var body: some View {
        Text("Set \(setIndex + 1) of \(setCount)")
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Set \(setIndex + 1) of \(setCount)")
    }
}

#Preview("First of four") {
    SetPositionBadgeView(setIndex: 0, setCount: 4)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Mid-session") {
    SetPositionBadgeView(setIndex: 1, setCount: 4)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Last set") {
    SetPositionBadgeView(setIndex: 3, setCount: 4)
        .padding()
        .background(Theme.Colors.canvas)
}
