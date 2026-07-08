import Charts
import SwiftUI
import SpottersaurusKit

struct TonnageChartView: View {
    var points: [PerformanceAnalytics.TonnagePoint]

    var body: some View {
        AnalyticsChartCardView(title: "Volume") {
            if points.isEmpty {
                AnalyticsEmptyChartView()
            } else {
                Chart(Array(points.enumerated()), id: \.offset) { item in
                    BarMark(
                        x: .value("Date", item.element.date),
                        y: .value("Tonnage", item.element.tonnageKg)
                    )
                    .foregroundStyle(Theme.Colors.dinoGreen)
                }
                .chartYAxisLabel("kg")
                .frame(height: 220)
            }
        }
    }
}
