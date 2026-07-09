import SwiftData
import SwiftUI
import SpottersaurusKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]

    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            List {
                if viewModel.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished Watch sessions will land here.")
                    )
                } else {
                    ForEach(viewModel.sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            HistorySessionRowView(session: session, viewModel: viewModel)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .onChange(of: sessions, initial: true) { _, newValue in
                viewModel.update(with: newValue)
            }
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
