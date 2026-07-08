import SwiftUI
import SpottersaurusKit

struct SessionSummaryCardView: View {
    var session: WorkoutSession
    var viewModel: HistoryViewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Label(session.source.rawValue.capitalized, systemImage: session.source == .watch ? "applewatch" : "iphone")
                    .font(.system(.headline, design: .rounded, weight: .bold))

                HStack(spacing: Theme.Spacing.sm) {
                    HistoryMetricLineView(label: "SETS", value: "\(viewModel.orderedSets(in: session).count)")
                    HistoryMetricLineView(
                        label: "TONNAGE",
                        value: "\(session.totalTonnageKg.formatted(.number.precision(.fractionLength(0)))) kg"
                    )
                }
            }
        }
    }
}
