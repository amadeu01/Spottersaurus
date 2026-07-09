import SwiftUI
import SpottersaurusKit

struct LiveWatchStatusCardView: View {
    var tick: LiveTickEnvelope?
    var receivedAt: Date?
    var importMessage: String
    var connectionStatus: ConnectionStatus = .inactive

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Label("Watch Live", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                    WatchConnectionChip(status: connectionStatus)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    liveMetric("REPS", tick.map { "\($0.repCount)" } ?? "--")
                    liveMetric("VEL", tick.map { "\($0.currentVelocityMS.formatted(.number.precision(.fractionLength(2))))" } ?? "--")
                    liveMetric("HR", tick.map { "\($0.heartRateBPM.formatted(.number.precision(.fractionLength(0))))" } ?? "--")
                }

                Text(importMessage)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func liveMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .monospacedDigit()
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Live tick") {
    ScrollView {
        LiveWatchStatusCardView(
            tick: LiveTickEnvelope(repCount: 3, currentVelocityMS: 0.42, heartRateBPM: 132, elapsedSeconds: 18),
            receivedAt: .now,
            importMessage: "Last import: Bench Press · 5 reps",
            connectionStatus: .connected
        )
        .padding()
    }
    .background(Theme.Colors.canvas)
}

#Preview("No live data") {
    ScrollView {
        LiveWatchStatusCardView(
            tick: nil,
            receivedAt: nil,
            importMessage: "No sessions imported yet.",
            connectionStatus: .pairedNotReachable
        )
        .padding()
    }
    .background(Theme.Colors.canvas)
}
