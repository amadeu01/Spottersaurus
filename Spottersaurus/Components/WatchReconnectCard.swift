//
//  WatchReconnectCard.swift
//  Spottersaurus
//
//  Compact Today-tab status card for the Watch connection (Phase 0.2 R3).
//  Shown only while no Live Session is active — S1's `InWorkoutView` owns
//  the "live" surface, so this never competes with it (see `TodayView`'s
//  gate on `LiveSessionMonitor.shared.state.phase`).
//
//  For anything short of `.connected` this explains what's wrong and offers
//  a genuine reconnect affordance: the button re-activates the local
//  `WCSession` (`WatchLink.reactivate()`), paired with an honest "open
//  Spottersaurus on your Watch" hint — the phone cannot force Watch
//  reachability, pairing, or app installation, so this is a real retry, not
//  a decorative button.
//

import SwiftUI
import SpottersaurusKit

struct WatchReconnectCard: View {
    var status: ConnectionStatus
    var onReconnect: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label(title, systemImage: symbolName)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Spacer()
                    WatchConnectionChip(status: status)
                }

                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)

                if showsReconnectButton {
                    Button(action: onReconnect) {
                        Label("Retry Connection", systemImage: "arrow.clockwise")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.brandOrange)
                }
            }
        }
    }

    private var showsReconnectButton: Bool {
        switch status {
        case .connected: false
        case .pairedNotReachable, .appNotInstalled, .notPaired, .inactive: true
        }
    }

    private var title: String {
        switch status {
        case .connected: "Watch connected"
        case .pairedNotReachable: "Watch unreachable"
        case .appNotInstalled: "Watch app not installed"
        case .notPaired: "No Watch paired"
        case .inactive: "Connecting to Watch…"
        }
    }

    private var detail: String {
        switch status {
        case .connected:
            "Live sessions will appear here automatically."
        case .pairedNotReachable:
            "Open Spottersaurus on your Apple Watch, then retry — the phone can only re-check the connection, not force it."
        case .appNotInstalled:
            "Install Spottersaurus on your Apple Watch from the Watch app on this iPhone, then retry."
        case .notPaired:
            "Pair an Apple Watch in the Watch app to run live sessions."
        case .inactive:
            "Still finishing activation. Retry if this doesn't clear on its own."
        }
    }

    private var symbolName: String {
        switch status {
        case .connected: "checkmark.circle.fill"
        case .pairedNotReachable: "applewatch.slash"
        case .appNotInstalled: "arrow.down.circle"
        case .notPaired: "applewatch.slash"
        case .inactive: "ellipsis.circle"
        }
    }
}

#Preview("Connected") {
    WatchReconnectCard(status: .connected, onReconnect: {})
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Unreachable - reconnect") {
    WatchReconnectCard(status: .pairedNotReachable, onReconnect: {})
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Not paired / app not installed") {
    VStack(spacing: Theme.Spacing.md) {
        WatchReconnectCard(status: .notPaired, onReconnect: {})
        WatchReconnectCard(status: .appNotInstalled, onReconnect: {})
    }
    .padding()
    .background(Theme.Colors.canvas)
}
