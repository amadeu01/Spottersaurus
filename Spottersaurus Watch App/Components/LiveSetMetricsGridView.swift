import SwiftUI
import SpottersaurusKit

struct LiveSetMetricsGridView: View {
    var velocityMS: Double
    var heartRate: Int
    var weightKg: Double
    var restText: String
    var targetReps: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                LiveSetMetricTile(label: "VEL", value: String(format: "%.2f", velocityMS), unit: "m/s")
                LiveSetMetricTile(label: "HR", value: "\(heartRate)", unit: "bpm")
            }
            HStack(spacing: Theme.Spacing.sm) {
                LiveSetMetricTile(label: "LOAD", value: String(format: "%.1f", weightKg), unit: "kg")
                LiveSetMetricTile(label: "REPS", value: targetReps, unit: nil)
            }
            HStack(spacing: Theme.Spacing.sm) {
                LiveSetMetricTile(label: "REST", value: restText, unit: nil)
            }
        }
    }
}

#Preview {
    LiveSetMetricsGridView(
        velocityMS: 0.42,
        heartRate: 128,
        weightKg: 100,
        restText: "1:30",
        targetReps: "3 of 5"
    )
    .padding()
    .background(Theme.Colors.canvas)
}
