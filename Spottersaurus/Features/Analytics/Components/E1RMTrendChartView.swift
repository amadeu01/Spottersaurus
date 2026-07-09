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

#Preview("With data") {
    let calendar = Calendar.current
    let points: [PerformanceAnalytics.TrendPoint] = (0..<4).map { offset in
        .init(
            date: calendar.date(byAdding: .weekOfYear, value: -offset, to: .now) ?? .now,
            e1RMKg: 130 + Double(offset) * 4
        )
    }.reversed()

    return ScrollView {
        E1RMTrendChartView(points: points)
            .padding()
    }
    .background(Theme.Colors.canvas)
}

#Preview("Empty") {
    E1RMTrendChartView(points: [])
        .padding()
        .background(Theme.Colors.canvas)
}
