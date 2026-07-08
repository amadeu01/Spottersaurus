import SwiftUI
import SpottersaurusKit

struct LiveSetCalibrationPanelView: View {
    var statusText: String
    var detailText: String
    var progress: Double
    var isCollecting: Bool
    var start: () -> Void
    var finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isCollecting ? "waveform.path" : "target")
                    .foregroundStyle(isCollecting ? Theme.Colors.caution : Theme.Colors.optimal)
                Text(statusText)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
            }

            ProgressView(value: progress)
                .tint(isCollecting ? Theme.Colors.caution : Theme.Colors.optimal)

            Text(detailText)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            HStack(spacing: Theme.Spacing.xs) {
                Button(action: start) {
                    Label(isCollecting ? "Restart" : "Warmup", systemImage: "flame.fill")
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.brandOrange)

                Button(action: finish) {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.optimal)
                .disabled(!isCollecting)
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}
