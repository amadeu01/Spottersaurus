import SwiftUI
import SpottersaurusKit

enum LiveSetCrownMode {
    case load
    case reps
}

struct LiveSetCrownModeControlView: View {
    var mode: LiveSetCrownMode
    var selectLoad: () -> Void
    var selectReps: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: selectLoad) {
                Image(systemName: "scalemass.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(mode == .load ? Theme.Colors.brandOrange : .secondary)

            Button(action: selectReps) {
                Image(systemName: "number")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(mode == .reps ? Theme.Colors.brandOrange : .secondary)
        }
    }
}
