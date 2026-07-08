import SwiftUI
import SpottersaurusKit

struct LiveWatchStatusCardView: View {
    var tick: LiveTickEnvelope?
    var receivedAt: Date?
    var importMessage: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Label("Watch Live", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                    Text(statusText)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(tick == nil ? .secondary : Theme.Colors.optimal)
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

    private var statusText: String {
        guard let receivedAt else { return "WAITING" }
        return receivedAt.formatted(date: .omitted, time: .standard)
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
