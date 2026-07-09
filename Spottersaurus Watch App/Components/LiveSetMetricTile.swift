import SwiftUI
import SpottersaurusKit

struct LiveSetMetricTile: View {
    var label: String
    var value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                if let unit {
                    Text(unit)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview("With unit") {
    LiveSetMetricTile(label: "VEL", value: "0.42", unit: "m/s")
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("No unit") {
    LiveSetMetricTile(label: "REPS", value: "3 of 5", unit: nil)
        .padding()
        .background(Theme.Colors.canvas)
}
