import SwiftData
import SwiftUI
import SpottersaurusKit

struct TodayView: View {
    @Environment(\.plannerDependencies) private var dependencies
    @Query private var programs: [Program]
    @Query private var maxes: [UserMaxes]
    @State private var viewModel = TodayViewModel()
    @State private var watchMonitor = PhoneWatchSessionMonitor.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    WatchConnectionChip(status: watchMonitor.connectionStatus)
                    LiveWatchStatusCardView(
                        tick: watchMonitor.lastTick,
                        receivedAt: watchMonitor.lastTickReceivedAt,
                        importMessage: watchMonitor.lastImportMessage,
                        connectionStatus: watchMonitor.connectionStatus
                    )

                    if let program = viewModel.activeProgram(from: programs),
                       let day = viewModel.todaysProgramDay(in: program) {
                        TodaySessionCard(program: program, day: day, maxes: maxes)
                        PrimaryButton("Send to Watch", systemImage: "applewatch", tint: Theme.Colors.brandOrange) {
                            Task {
                                await viewModel.sendPlannedSession(program: program, day: day, maxes: maxes, using: dependencies)
                            }
                        }
                        Text(viewModel.sendStatus.rawValue)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        watchControls
                    } else {
                        EmptyPlannerStateView()
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.canvas.opacity(0.04))
            .navigationTitle("Today")
        }
    }

    private var watchControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    Task {
                        await viewModel.sendWatchCommand(.startWarmup, using: dependencies)
                    }
                } label: {
                    Label("Warmup", systemImage: "figure.strengthtraining.traditional")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await viewModel.sendWatchCommand(.startWorkout, using: dependencies)
                    }
                } label: {
                    Label("Start", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.brandOrange)
            }

            if let commandStatus = viewModel.commandStatus {
                Text(commandStatus.rawValue)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Spottersaurus")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("With active program") {
    TodayView()
        .modelContainer(PreviewSeed.seededContainer())
}

#Preview("No program loaded") {
    TodayView()
        .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
