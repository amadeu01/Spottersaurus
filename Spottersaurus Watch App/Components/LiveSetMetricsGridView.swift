import SwiftUI
import SpottersaurusKit

struct LiveSetMetricsGridView: View {
    var velocityMS: Double
    var heartRate: Int
    var weightKg: Double
    var restText: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                LiveSetMetricTile(label: "VEL", value: String(format: "%.2f", velocityMS), unit: "m/s")
                LiveSetMetricTile(label: "HR", value: "\(heartRate)", unit: "bpm")
            }
            HStack(spacing: Theme.Spacing.sm) {
                LiveSetMetricTile(label: "LOAD", value: String(format: "%.1f", weightKg), unit: "kg")
                LiveSetMetricTile(label: "REST", value: restText, unit: nil)
            }
        }
    }
}
