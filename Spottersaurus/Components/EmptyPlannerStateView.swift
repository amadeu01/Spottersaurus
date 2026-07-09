import SwiftUI
import SpottersaurusKit

struct EmptyPlannerStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.Colors.brandOrange)
            Text("No Program Loaded")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Load a preset from Programs to start planning sessions.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

#Preview {
    ScrollView {
        EmptyPlannerStateView()
            .padding()
    }
    .background(Theme.Colors.canvas)
}
