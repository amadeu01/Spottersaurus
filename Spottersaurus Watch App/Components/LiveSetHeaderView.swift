import SwiftUI
import SpottersaurusKit

struct LiveSetHeaderView: View {
    var exerciseName: String
    var statusText: String
    var statusSymbol: String
    var tone: LiveSetTone
    var alertStage: AlertStage

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseName)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(tone.color)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Image(systemName: statusSymbol)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(tone.color)
                .symbolEffect(.pulse, options: .repeating, value: alertStage)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Optimal") {
    LiveSetHeaderView(
        exerciseName: "Bench Press",
        statusText: "Repping",
        statusSymbol: "checkmark.circle.fill",
        tone: .optimal,
        alertStage: .none
    )
    .padding()
    .background(Theme.Colors.canvas)
}

#Preview("Grinding") {
    LiveSetHeaderView(
        exerciseName: "Bench Press",
        statusText: "Grinding",
        statusSymbol: "exclamationmark.triangle.fill",
        tone: .caution,
        alertStage: .grinding
    )
    .padding()
    .background(Theme.Colors.canvas)
}

#Preview("Rack It") {
    LiveSetHeaderView(
        exerciseName: "Bench Press",
        statusText: "RACK IT",
        statusSymbol: "hand.raised.fill",
        tone: .alert,
        alertStage: .rackIt
    )
    .padding()
    .background(Theme.Colors.canvas)
}
