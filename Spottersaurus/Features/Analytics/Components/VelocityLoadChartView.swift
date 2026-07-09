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

#Preview("With data") {
    ScrollView {
        VelocityLoadChartView(points: [
            .init(weightKg: 60, meanVelocityMS: 0.65),
            .init(weightKg: 80, meanVelocityMS: 0.52),
            .init(weightKg: 100, meanVelocityMS: 0.38),
        ])
        .padding()
    }
    .background(Theme.Colors.canvas)
}

#Preview("Empty") {
    VelocityLoadChartView(points: [])
        .padding()
        .background(Theme.Colors.canvas)
}
