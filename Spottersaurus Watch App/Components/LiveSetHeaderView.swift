import SwiftUI
import SpottersaurusKit

struct LiveSetHeaderView: View {
    var exerciseName: String
    var statusText: String
    var statusSymbol: String
    var tone: LiveSetTone
    var alertStage: AlertStage

    /// AOD calm variant (Phase 0.2 V1): the wrist-down Always-On Display must
    /// be static — a pulsing glyph frozen mid-pulse would look broken, and
    /// continuous animation is a burn-in/battery concern. Color/glyph still
    /// reflect the current Alert Stage; only the motion is suppressed.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

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

            statusGlyph
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        if isLuminanceReduced {
            Image(systemName: statusSymbol)
        } else {
            Image(systemName: statusSymbol)
                .symbolEffect(.pulse, options: .repeating, value: alertStage)
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

#Preview("AOD — Grinding") {
    LiveSetHeaderView(
        exerciseName: "Bench Press",
        statusText: "Grinding",
        statusSymbol: "exclamationmark.triangle.fill",
        tone: .caution,
        alertStage: .grinding
    )
    .padding()
    .background(Theme.Colors.canvas)
    .environment(\.isLuminanceReduced, true)
}

#Preview("AOD — Rack It") {
    LiveSetHeaderView(
        exerciseName: "Bench Press",
        statusText: "RACK IT",
        statusSymbol: "hand.raised.fill",
        tone: .alert,
        alertStage: .rackIt
    )
    .padding()
    .background(Theme.Colors.canvas)
    .environment(\.isLuminanceReduced, true)
}
