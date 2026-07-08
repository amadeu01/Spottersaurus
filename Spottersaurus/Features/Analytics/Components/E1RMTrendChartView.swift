import Charts
import SwiftUI
import SpottersaurusKit

struct E1RMTrendChartView: View {
    var points: [PerformanceAnalytics.TrendPoint]

    var body: some View {
        AnalyticsChartCardView(title: "e1RM Trend") {
            if points.isEmpty {
                AnalyticsEmptyChartView()
            } else {
                Chart(Array(points.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value("Date", item.element.date),
                        y: .value("e1RM", item.element.e1RMKg)
                    )
                    .foregroundStyle(Theme.Colors.brandOrange)
                    PointMark(
                        x: .value("Date", item.element.date),
                        y: .value("e1RM", item.element.e1RMKg)
                    )
                    .foregroundStyle(Theme.Colors.brandOrange)
                }
                .chartYAxisLabel("kg")
                .frame(height: 220)
            }
        }
    }
}
