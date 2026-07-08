//
//  RingGauge.swift
//  SpottersaurusKit
//
//  Native port of the web brief's `strokeDasharray` progress rings: a
//  `Circle().trim(from:to:)` gauge that starts at 12 o'clock and sweeps
//  clockwise. Used for the per-rep close-out ring on the live set screen and
//  for rest-timer / calibration progress on both platforms.
//

#if canImport(SwiftUI)
import SwiftUI

/// A circular progress gauge with optional centered content, e.g. a rep
/// count or a countdown. Progress animates with `.easeOut` on change.
public struct RingGauge<Content: View>: View {
    /// 0...1 fraction of the ring to fill. Values outside the range are clamped.
    public var progress: Double
    /// Ring tint. Defaults to the "optimal" brand green.
    public var tint: Color
    /// Stroke width in points.
    public var lineWidth: Double
    /// Content laid out in the center of the ring, e.g. a `MetricReadout`.
    @ViewBuilder public var content: () -> Content

    public init(
        progress: Double,
        tint: Color = Theme.Colors.optimal,
        lineWidth: Double = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
        self.content = content
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Trim starts at 3 o'clock by default; rotate to start at 12.
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)

            content()
        }
    }
}

public extension RingGauge where Content == EmptyView {
    /// Convenience initializer for a bare ring with no center content.
    init(progress: Double, tint: Color = Theme.Colors.optimal, lineWidth: Double = 12) {
        self.init(progress: progress, tint: tint, lineWidth: lineWidth) { EmptyView() }
    }
}

#Preview("RingGauge") {
    ZStack {
        Theme.Colors.canvas.ignoresSafeArea()
        RingGauge(progress: 0.72, tint: Theme.Colors.optimal, lineWidth: 14) {
            MetricReadout(label: "Rep", value: "3", unit: "of 5")
        }
        .frame(width: 180, height: 180)
    }
}
#endif
