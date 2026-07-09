import Charts
import SwiftUI
import SpottersaurusKit

struct SpotterFrequencyChartView: View {
    var frequency: PerformanceAnalytics.SpotterEventFrequency

    var body: some View {
        AnalyticsChartCardView(title: "Spotter Events") {
            Chart(data, id: \.label) { item in
                BarMark(
                    x: .value("Stage", item.label),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(item.label == "Rack It" ? Theme.Colors.alert : Theme.Colors.caution)
            }
            .frame(height: 180)
        }
    }

    private var data: [(label: String, count: Int)] {
        [
            ("Grind", frequency.grindCount),
            ("Rack It", frequency.rackItCount)
        ]
    }
}

#Preview {
    SpotterFrequencyChartView(frequency: .init(grindCount: 4, rackItCount: 1))
        .padding()
        .background(Theme.Colors.canvas)
}
