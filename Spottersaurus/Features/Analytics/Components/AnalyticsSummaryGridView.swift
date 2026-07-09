import SwiftUI
import SpottersaurusKit

struct AnalyticsSummaryGridView: View {
    var bestE1RM: String
    var totalTonnage: String
    var spotterFrequency: PerformanceAnalytics.SpotterEventFrequency

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
            AnalyticsMetricCardView(label: "BEST e1RM", value: "\(bestE1RM) kg", systemImage: "bolt.fill")
            AnalyticsMetricCardView(label: "TONNAGE", value: "\(totalTonnage) kg", systemImage: "scalemass.fill")
            AnalyticsMetricCardView(label: "GRINDS", value: "\(spotterFrequency.grindCount)", systemImage: "exclamationmark.triangle.fill")
            AnalyticsMetricCardView(label: "RACK IT", value: "\(spotterFrequency.rackItCount)", systemImage: "hand.raised.fill")
        }
    }
}

#Preview {
    AnalyticsSummaryGridView(
        bestE1RM: "142",
        totalTonnage: "2,340",
        spotterFrequency: .init(grindCount: 4, rackItCount: 1)
    )
    .padding()
    .background(Theme.Colors.canvas)
}
