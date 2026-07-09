import SwiftUI
import SpottersaurusKit

struct AnalyticsMetricCardView: View {
    var label: String
    var value: String
    var systemImage: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Colors.brandOrange)
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
        AnalyticsMetricCardView(label: "BEST e1RM", value: "142 kg", systemImage: "bolt.fill")
        AnalyticsMetricCardView(label: "TONNAGE", value: "2,340 kg", systemImage: "scalemass.fill")
    }
    .padding()
    .background(Theme.Colors.canvas)
}
