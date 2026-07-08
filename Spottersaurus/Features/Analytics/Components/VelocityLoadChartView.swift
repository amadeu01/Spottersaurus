import Charts
import SwiftUI
import SpottersaurusKit

struct VelocityLoadChartView: View {
    var points: [PerformanceAnalytics.VelocityLoadPoint]

    var body: some View {
        AnalyticsChartCardView(title: "Velocity at Load") {
            if points.isEmpty {
                AnalyticsEmptyChartView()
            } else {
                Chart(Array(points.enumerated()), id: \.offset) { item in
                    PointMark(
                        x: .value("Load", item.element.weightKg),
                        y: .value("Velocity", item.element.meanVelocityMS)
                    )
                    .foregroundStyle(Theme.Colors.brandOrange)
                }
                .chartXAxisLabel("kg")
                .chartYAxisLabel("m/s")
                .frame(height: 220)
            }
        }
    }
}
