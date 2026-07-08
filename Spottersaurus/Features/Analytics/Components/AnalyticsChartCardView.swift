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
