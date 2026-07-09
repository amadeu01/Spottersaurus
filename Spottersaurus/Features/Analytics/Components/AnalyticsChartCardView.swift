import SwiftUI
import SpottersaurusKit

struct AnalyticsChartCardView<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                content
            }
        }
    }
}

#Preview {
    ScrollView {
        AnalyticsChartCardView(title: "e1RM Trend") {
            Text("Chart content goes here")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
        .padding()
    }
    .background(Theme.Colors.canvas)
}
