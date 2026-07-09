import SwiftUI
import SpottersaurusKit

struct LiveSetMetricsGridView: View {
    /// The last completed rep's Mean Concentric Velocity (Phase 0.2 V2). `nil`
    /// before the set's first rep completes — there's no reading yet, so the
    /// tile shows "--" rather than a placeholder number.
    var velocityMS: Double?
    var heartRate: Int
    var weightKg: Double
    var restText: String
    var targetReps: String

    /// AOD calm variant (Phase 0.2 V1): velocity is a per-rep VBT headline
    /// (Mean Concentric Velocity, resolved at rep completion — see ADR 0001),
    /// not a continuous trace, but the Always-On Display must still avoid any
    /// churn. Freeze the displayed figure to the last value seen while the
    /// screen was fully lit rather than tracking live updates while dimmed —
    /// same tile, same layout, just static.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var frozenVelocityMS: Double?

    private var displayedVelocityMS: Double? {
        isLuminanceReduced ? frozenVelocityMS : velocityMS
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                LiveSetMetricTile(
                    label: "VEL",
                    value: displayedVelocityMS.map { String(format: "%.2f", $0) } ?? "--",
                    unit: "m/s"
                )
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
        .onAppear { frozenVelocityMS = velocityMS }
        .onChange(of: velocityMS) { _, newValue in
            guard !isLuminanceReduced else { return }
            frozenVelocityMS = newValue
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

#Preview("AOD") {
    LiveSetMetricsGridView(
        velocityMS: 0.42,
        heartRate: 128,
        weightKg: 100,
        restText: "1:30",
        targetReps: "3 of 5"
    )
    .padding()
    .background(Theme.Colors.canvas)
    .environment(\.isLuminanceReduced, true)
}

#Preview("No reading yet") {
    LiveSetMetricsGridView(
        velocityMS: nil,
        heartRate: 0,
        weightKg: 100,
        restText: "--",
        targetReps: "0 of 5"
    )
    .padding()
    .background(Theme.Colors.canvas)
}
