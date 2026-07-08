//
//  MetricReadout.swift
//  SpottersaurusKit
//
//  Native port of the web brief's `font-mono` metric readouts: a small
//  uppercase caption over a large monospaced-digit value, optionally suffixed
//  with a unit. Used throughout the live set screen (rep count, velocity, HR,
//  weight) and history/review charts.
//

#if canImport(SwiftUI)
import SwiftUI

/// A labeled live-metric readout: caption + big monospaced-digit value + unit.
public struct MetricReadout: View {
    /// Small uppercase caption above the value, e.g. "VELOCITY".
    public var label: String
    /// The formatted metric value, e.g. "0.42" or "12".
    public var value: String
    /// Optional trailing unit, e.g. "m/s" or "bpm".
    public var unit: String?
    /// Point size of the value text. Defaults to a size legible at a glance.
    public var valueSize: Double

    public init(label: String, value: String, unit: String? = nil, valueSize: Double = 40) {
        self.label = label
        self.value = value
        self.unit = unit
        self.valueSize = valueSize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label.uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("MetricReadout") {
    ZStack {
        Theme.Colors.canvas.ignoresSafeArea()
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            MetricReadout(label: "Reps", value: "3", unit: "of 5")
            MetricReadout(label: "Concentric Velocity", value: "0.42", unit: "m/s")
            MetricReadout(label: "Heart Rate", value: "148", unit: "bpm")
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.lg)
    }
}
#endif
