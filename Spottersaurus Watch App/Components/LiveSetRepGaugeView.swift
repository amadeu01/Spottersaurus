import SwiftUI
import SpottersaurusKit

struct LiveSetRepGaugeView: View {
    var repCount: Int
    var targetReps: Int
    var progress: Double
    var tone: LiveSetTone
    var alertStage: AlertStage

    /// AOD calm variant (Phase 0.2 V1): rep count stays live and readable on
    /// the Always-On Display, but without the numeric roll-over transition or
    /// the pulsing grind/RACK-IT border — a pulse frozen mid-scale on an OLED
    /// AOD would look like a rendering glitch, and it's a burn-in/battery
    /// concern besides.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        RingGauge(progress: progress, tint: tone.color, lineWidth: 10) {
            VStack(spacing: 0) {
                Text("\(repCount)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(isLuminanceReduced ? .identity : .numericText())
                Text("of \(targetReps)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 142, height: 142)
        .padding(.top, Theme.Spacing.xs)
        .overlay {
            if isLuminanceReduced {
                Circle()
                    .stroke(tone.color.opacity(alertStage == .none ? 0 : 0.8), lineWidth: 2)
            } else {
                Circle()
                    .stroke(tone.color.opacity(alertStage == .none ? 0 : 0.8), lineWidth: 2)
                    .scaleEffect(alertStage == .grinding ? 1.06 : 1)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: alertStage)
            }
        }
    }
}

#Preview("Optimal") {
    LiveSetRepGaugeView(repCount: 2, targetReps: 5, progress: 0.4, tone: .optimal, alertStage: .none)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Grinding") {
    LiveSetRepGaugeView(repCount: 4, targetReps: 5, progress: 0.8, tone: .caution, alertStage: .grinding)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Rack It") {
    LiveSetRepGaugeView(repCount: 5, targetReps: 5, progress: 1.0, tone: .alert, alertStage: .rackIt)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("AOD — Grinding") {
    LiveSetRepGaugeView(repCount: 4, targetReps: 5, progress: 0.8, tone: .caution, alertStage: .grinding)
        .padding()
        .background(Theme.Colors.canvas)
        .environment(\.isLuminanceReduced, true)
}

#Preview("AOD — Rack It") {
    LiveSetRepGaugeView(repCount: 5, targetReps: 5, progress: 1.0, tone: .alert, alertStage: .rackIt)
        .padding()
        .background(Theme.Colors.canvas)
        .environment(\.isLuminanceReduced, true)
}
