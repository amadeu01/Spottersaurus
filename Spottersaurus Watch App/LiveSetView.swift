import SwiftUI
import SpottersaurusKit

struct LiveSetView: View {
    @State private var lifecycle = SetLifecycleController(restSeconds: 90)
    @State private var targetReps = 5.0
    @State private var weightKg = 100.0
    @State private var heartRate = 132
    @State private var velocityMS = 0.42
    @State private var restElapsed = 0.0
    @FocusState private var crownFocused: Bool

    var body: some View {
        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            if lifecycle.alertStage == .rackIt {
                rackItOverlay
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        header
                        repGauge
                        metricGrid
                        controls
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.impact(weight: .medium), trigger: lifecycle.alertStage)
        .digitalCrownRotation(
            $weightKg,
            from: 20,
            through: 320,
            by: 2.5,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .focusable()
        .focused($crownFocused)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bench Press")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Image(systemName: statusSymbol)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, options: .repeating, value: lifecycle.alertStage)
                .accessibilityHidden(true)
        }
    }

    private var repGauge: some View {
        RingGauge(progress: gaugeProgress, tint: statusColor, lineWidth: 10) {
            VStack(spacing: 0) {
                Text("\(lifecycle.repCount)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(Int(targetReps))")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 142, height: 142)
        .padding(.top, Theme.Spacing.xs)
        .overlay {
            Circle()
                .stroke(statusColor.opacity(borderOpacity), lineWidth: 2)
                .scaleEffect(lifecycle.alertStage == .grinding ? 1.06 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: lifecycle.alertStage)
        }
    }

    private var metricGrid: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                compactMetric("VEL", String(format: "%.2f", velocityMS), "m/s")
                compactMetric("HR", "\(heartRate)", "bpm")
            }
            HStack(spacing: Theme.Spacing.sm) {
                compactMetric("LOAD", String(format: "%.1f", weightKg), "kg")
                compactMetric("REST", restText, nil)
            }
        }
    }

    private func compactMetric(_ label: String, _ value: String, _ unit: String?) -> some View {
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

    private var controls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            switch lifecycle.state {
            case .idle, .complete:
                Button {
                    lifecycle.arm()
                    restElapsed = 0
                } label: {
                    Label("Arm", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.brandOrange)

            case .armed, .repping:
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        lifecycle.repCompleted()
                        velocityMS = max(0.18, velocityMS - 0.03)
                        heartRate += 3
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        lifecycle.handle(spotEvent: .init(
                            kind: .grinding,
                            timestamp: 0,
                            repIndex: lifecycle.repCount,
                            confidence: 0.72,
                            reason: .concentricTempo
                        ))
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.caution)

                    Button {
                        lifecycle.handle(spotEvent: .init(
                            kind: .rackIt,
                            timestamp: 0,
                            repIndex: lifecycle.repCount,
                            confidence: 0.94,
                            reason: .sustainedPin
                        ))
                    } label: {
                        Image(systemName: "hand.raised.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.alert)
                }

                Button {
                    if lifecycle.state == .armed {
                        lifecycle.repCompleted()
                    }
                    lifecycle.autoRack()
                    restElapsed = 0
                    lifecycle.restTick(elapsed: restElapsed)
                } label: {
                    Label("Rack", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)

            case .racked, .resting:
                Button {
                    restElapsed = lifecycle.restSeconds
                    lifecycle.restTick(elapsed: restElapsed)
                } label: {
                    Label("Rest Done", systemImage: "timer")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.optimal)
            }
        }
        .font(.system(.body, design: .rounded, weight: .bold))
    }

    private var rackItOverlay: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 42, weight: .heavy))
            Text("RACK IT")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Button {
                lifecycle.handle(spotEvent: .init(
                    kind: .resolved,
                    timestamp: 0,
                    repIndex: lifecycle.repCount,
                    confidence: 1,
                    reason: .manualTap
                ))
            } label: {
                Text("Resolved")
                    .frame(minWidth: 96, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Theme.Colors.alert)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.alert)
    }

    private var gaugeProgress: Double {
        if lifecycle.state == .resting || lifecycle.state == .racked {
            return min(max(restElapsed / lifecycle.restSeconds, 0), 1)
        }
        return min(Double(lifecycle.repCount) / max(targetReps, 1), 1)
    }

    private var restText: String {
        guard lifecycle.state == .resting || lifecycle.state == .racked else { return "--" }
        let remaining = max(Int(lifecycle.restSeconds - restElapsed), 0)
        return "\(remaining)s"
    }

    private var statusText: String {
        switch lifecycle.alertStage {
        case .rackIt:
            "RACK IT"
        case .grinding:
            "GRINDING"
        case .none:
            switch lifecycle.state {
            case .idle: "READY"
            case .armed: "ARMED"
            case .repping: "LIVE"
            case .racked, .resting: "REST"
            case .complete: "SET COMPLETE"
            }
        }
    }

    private var statusSymbol: String {
        switch lifecycle.alertStage {
        case .rackIt: "hand.raised.fill"
        case .grinding: "exclamationmark.triangle.fill"
        case .none: lifecycle.state == .resting ? "timer" : "waveform.path.ecg"
        }
    }

    private var statusColor: Color {
        switch lifecycle.alertStage {
        case .rackIt: Theme.Colors.alert
        case .grinding: Theme.Colors.caution
        case .none: Theme.Colors.optimal
        }
    }

    private var borderOpacity: Double {
        lifecycle.alertStage == .none ? 0 : 0.8
    }
}

#Preview {
    LiveSetView()
}
