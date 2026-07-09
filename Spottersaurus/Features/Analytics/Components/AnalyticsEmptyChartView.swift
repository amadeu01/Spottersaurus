import SwiftUI
import SpottersaurusKit

struct AnalyticsEmptyChartView: View {
    var body: some View {
        VStack {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("No data for this lift")
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

#Preview {
    AnalyticsEmptyChartView()
        .padding()
        .background(Theme.Colors.canvas)
}
