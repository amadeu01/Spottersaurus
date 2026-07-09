//
//  WatchConnectionChip.swift
//  Spottersaurus
//
//  Compact, reactive status pill reflecting `PhoneWatchSessionMonitor`'s
//  `ConnectionStatus`. Non-interactive (no tap target requirement) — a quick
//  glance so the lifter isn't guessing why Watch state looks stale.
//

import SwiftUI
import SpottersaurusKit

struct WatchConnectionChip: View {
    var status: ConnectionStatus

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbolName)
                .font(.system(.caption2, weight: .semibold))
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.15))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch status {
        case .connected: "Watch connected"
        case .pairedNotReachable: "Watch unreachable"
        case .appNotInstalled: "Install Watch app"
        case .notPaired: "No Watch paired"
        case .inactive: "Connecting…"
        }
    }

    private var symbolName: String {
        switch status {
        case .connected: "applewatch.radiowaves.left.and.right"
        case .pairedNotReachable: "applewatch.slash"
        case .appNotInstalled: "arrow.down.circle"
        case .notPaired: "applewatch.slash"
        case .inactive: "ellipsis.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .connected: Theme.Colors.optimal
        case .pairedNotReachable, .appNotInstalled: Theme.Colors.caution
        case .notPaired, .inactive: .secondary
        }
    }
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            WatchConnectionChip(status: status)
        }
    }
    .padding()
    .background(Theme.Colors.canvas)
}
