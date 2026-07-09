import SwiftData
import SwiftUI
import SpottersaurusKit

struct PlannerTabsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var maxes: [UserMaxes]

    private let viewModel = MaxesViewModel()

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "play.circle.fill") }

            ProgramsView()
                .tabItem { Label("Programs", systemImage: "list.bullet.rectangle") }

            ReviewView()
                .tabItem { Label("Review", systemImage: "chart.xyaxis.line") }

            MaxesView()
                .tabItem { Label("Maxes", systemImage: "gauge.with.dots.needle.67percent") }
        }
        .tint(Theme.Colors.brandOrange)
        .environment(\.plannerDependencies, .live)
        .onAppear {
            viewModel.ensureCompetitionMaxesExist(in: modelContext, existingMaxes: maxes)
            WatchLink.shared.configure(
                onLiveTick: { tick in
                    PhoneWatchSessionMonitor.shared.receiveLiveTick(tick)
                    LiveSessionMonitor.shared.receive(tick: tick)
                },
                onFinishedSession: { envelope in
                    LoggerGroup.iPhone.notice(.persistence, "importing finished session id=\(envelope.id) sets=\(envelope.sets.count)")
                    if let session = try? SessionImporter.importSession(envelope, into: modelContext) {
                        try? modelContext.save()
                        PhoneWatchSessionMonitor.shared.recordImport(envelope)
                        LoggerGroup.iPhone.notice(.persistence, "imported workout session id=\(session.id)")
                    }
                },
                onLifecycle: { event in
                    LiveSessionMonitor.shared.receive(lifecycle: event)
                }
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
