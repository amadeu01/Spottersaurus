import SwiftUI
import SpottersaurusKit

struct LiveSetControlsView: View {
    var state: SetLifecycleState
    var arm: () -> Void
    var completeRep: () -> Void
    var flagGrinding: () -> Void
    var rackIt: () -> Void
    var rack: () -> Void
    var finishRest: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            switch state {
            case .idle, .complete:
                Button(action: arm) {
                    Label("Arm", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.brandOrange)

            case .armed, .repping:
                liveButtons

                Button(action: rack) {
                    Label("Rack", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)

            case .racked, .resting:
                Button(action: finishRest) {
                    Label("Rest Done", systemImage: "timer")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.optimal)
            }
        }
        .font(.system(.body, design: .rounded, weight: .bold))
    }

    private var liveButtons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: completeRep) {
                Image(systemName: "plus")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button(action: flagGrinding) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.caution)

            Button(action: rackIt) {
                Image(systemName: "hand.raised.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.alert)
        }
    }
}
