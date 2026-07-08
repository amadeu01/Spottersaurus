import SwiftUI
import SpottersaurusKit

struct CompletedSetDetailCardView: View {
    var set: CompletedSet
    var viewModel: HistoryViewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(viewModel.setTitle(set))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(viewModel.setSubtitle(set))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    HistoryMetricLineView(label: "VELOCITY", value: viewModel.velocitySummary(set))
                    HistoryMetricLineView(label: "EVENTS", value: "\(set.spotterEvents.count)")
                }

                if !set.spotterEvents.isEmpty {
                    SpotterEventsView(events: set.spotterEvents)
                }

                if !set.orderedRepMetrics.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Rep Metrics")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.secondary)
                        ForEach(set.orderedRepMetrics) { rep in
                            RepMetricRowView(rep: rep)
                        }
                    }
                }
            }
        }
    }
}
