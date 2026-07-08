import SwiftUI
import SpottersaurusKit

struct RackItOverlayView: View {
    var resolveAlert: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 42, weight: .heavy))
            Text("RACK IT")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Button(action: resolveAlert) {
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
}
