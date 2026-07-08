import SwiftData
import SwiftUI
import SpottersaurusKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]

    private let viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished Watch sessions will land here.")
                    )
                } else {
                    ForEach(viewModel.sortedSessions(sessions)) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            HistorySessionRowView(session: session, viewModel: viewModel)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .refreshable {
                viewModel.refreshSavedSessionCount(in: modelContext)
            }
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
