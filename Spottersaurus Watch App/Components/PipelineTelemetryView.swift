//
//  PipelineTelemetryView.swift
//  Spottersaurus Watch App
//
//  Subtle, always-on micro-readout proving the live sensor pipeline is
//  actually running — not mocked. Shows motion sensor liveness + rate, HR
//  liveness, and how stale the last motion sample is, so a lifter/dev can
//  glance and confirm the auto-spotter is watching real data. Deliberately
//  tiny (single caption row) so it doesn't compete with the rep gauge or
//  RACK IT overlay; renders nothing when the pipeline has never started at
//  all so it doesn't clutter the idle/pre-arm screen.
//

import SwiftUI
import SpottersaurusKit

struct PipelineTelemetryView: View {
    var telemetry: LivePipelineTelemetry

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            dot(isOn: telemetry.sensorRunning)
            Text(rateText)
                .monospacedDigit()

            dot(isOn: telemetry.hrFlowing)
            Text("HR")

            Text(ageText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption2, design: .rounded, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func dot(isOn: Bool) -> some View {
        Image(systemName: isOn ? "circle.fill" : "circle")
            .font(.system(size: 6))
            .foregroundStyle(isOn ? Theme.Colors.optimal : Theme.Colors.caution)
    }

    private var rateText: String {
        String(format: "%.0f/s", telemetry.samplesPerSecond)
    }

    private var ageText: String {
        guard let age = telemetry.lastSampleAge else { return "--" }
        if age < 10 {
            return String(format: "%.1fs", age)
        }
        return "stale"
    }

    private var accessibilityLabel: String {
        let sensorText = telemetry.sensorRunning ? "Sensor running, \(rateText)" : "Sensor stopped"
        let hrText = telemetry.hrFlowing ? "heart rate flowing" : "heart rate not flowing"
        let ageDescription = telemetry.lastSampleAge.map { "last sample \(String(format: "%.1f", $0)) seconds ago" } ?? "no samples received"
        return "\(sensorText), \(hrText), \(ageDescription)"
    }
}

#Preview("Alive") {
    PipelineTelemetryView(
        telemetry: LivePipelineTelemetry(
            sensorRunning: true,
            hrFlowing: true,
            samplesPerSecond: 52,
            lastSampleAge: 0.1
        )
    )
    .padding()
    .background(Theme.Colors.canvas)
}

#Preview("Stalled") {
    PipelineTelemetryView(
        telemetry: LivePipelineTelemetry(
            sensorRunning: true,
            hrFlowing: false,
            samplesPerSecond: 0,
            lastSampleAge: 12
        )
    )
    .padding()
    .background(Theme.Colors.canvas)
}

#Preview("Idle") {
    PipelineTelemetryView(telemetry: .idle)
        .padding()
        .background(Theme.Colors.canvas)
}
