//
//  PhoneConnectionChip.swift
//  Spottersaurus Watch App
//
//  Compact reachability chip mirroring `WatchConnectionChip` on the iPhone
//  side, driven by `WatchPlannedSessionStore`'s `ConnectionStatus`. watchOS's
//  `WCSession` can't report `isPaired`/`isWatchAppInstalled` (see
//  `WatchPlannedSessionStore.connectionStatus`), so in practice this chip
//  only ever renders three of the five `ConnectionStatus` cases: connected,
//  pairedNotReachable, and inactive. The other two are handled for
//  exhaustiveness but shouldn't occur on-device.
//

import SwiftUI
import SpottersaurusKit

struct PhoneConnectionChip: View {
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
        case .connected: "iPhone connected"
        case .pairedNotReachable, .appNotInstalled: "iPhone unreachable"
        case .notPaired, .inactive: "Connecting…"
        }
    }

    private var symbolName: String {
        switch status {
        case .connected: "iphone.gen3.radiowaves.left.and.right"
        case .pairedNotReachable, .appNotInstalled: "iphone.slash"
        case .notPaired, .inactive: "ellipsis.circle"
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

#Preview("Connected") {
    PhoneConnectionChip(status: .connected)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Unreachable") {
    PhoneConnectionChip(status: .pairedNotReachable)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Connecting") {
    PhoneConnectionChip(status: .inactive)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            PhoneConnectionChip(status: status)
        }
    }
    .padding()
    .background(Theme.Colors.canvas)
}
