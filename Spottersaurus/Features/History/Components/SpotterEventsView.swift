import SwiftUI
import SpottersaurusKit

struct SpotterEventsView: View {
    var events: [SpotterEvent]

    var body: some View {
        FlowLayout(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                SpotterEventPillView(event: event)
            }
        }
    }
}

private struct SpotterEventPillView: View {
    var event: SpotterEvent

    var body: some View {
        Label(label, systemImage: event.stage == .rackIt ? "hand.raised.fill" : "exclamationmark.triangle.fill")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .foregroundStyle(.white)
            .background(tint, in: Capsule())
    }

    private var label: String {
        let rep = event.repIndex.map { " rep \($0 + 1)" } ?? ""
        return "\(event.stage == .rackIt ? "Rack It" : "Grind")\(rep)"
    }

    private var tint: Color {
        event.stage == .rackIt ? Theme.Colors.alert : Theme.Colors.caution
    }
}

#Preview {
    SpotterEventsView(events: [
        SpotterEvent(stage: .grind, timestamp: 12, repIndex: 2),
        SpotterEvent(stage: .rackIt, timestamp: 19, repIndex: 4),
    ])
    .padding()
}
