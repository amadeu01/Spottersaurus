import SwiftData
import SwiftUI
import SpottersaurusKit

struct SessionDetailView: View {
    var session: WorkoutSession

    private let viewModel = HistoryViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SessionSummaryCardView(session: session, viewModel: viewModel)

                ForEach(viewModel.orderedSets(in: session)) { set in
                    CompletedSetDetailCardView(set: set, viewModel: viewModel)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.canvas.opacity(0.04))
        .navigationTitle(viewModel.sessionTitle(session))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: PreviewSeed.workoutSession())
    }
    .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
