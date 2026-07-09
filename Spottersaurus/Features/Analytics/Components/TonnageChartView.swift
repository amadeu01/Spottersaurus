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

#Preview("With data") {
    let calendar = Calendar.current
    let points: [PerformanceAnalytics.TonnagePoint] = (0..<4).map { offset in
        .init(
            date: calendar.date(byAdding: .weekOfYear, value: -offset, to: .now) ?? .now,
            tonnageKg: 2200 + Double(offset) * 150
        )
    }.reversed()

    return ScrollView {
        TonnageChartView(points: points)
            .padding()
    }
    .background(Theme.Colors.canvas)
}

#Preview("Empty") {
    TonnageChartView(points: [])
        .padding()
        .background(Theme.Colors.canvas)
}
