import SwiftUI
import SpottersaurusKit

struct HistorySessionRowView: View {
    var session: WorkoutSession
    var viewModel: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(viewModel.sessionTitle(session))
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(viewModel.sessionSubtitle(session))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
