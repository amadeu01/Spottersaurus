import SwiftData
import SwiftUI
import SpottersaurusKit

struct TodayView: View {
    /// How recent `lastTickReceivedAt` must be for a Watch session to be
    /// considered "live". Chosen to comfortably span the gap between ticks
    /// during an active set while disappearing quickly once they stop.
    static let liveSessionWindow: TimeInterval = 10

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

                    // `TimelineView` ticks once a second purely so `isLiveSessionActive`
                    // re-evaluates and the card disappears shortly after ticks stop,
                    // even with no new data arriving from the Watch.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if isLiveSessionActive(at: context.date) {
                            LiveWatchStatusCardView(
                                tick: watchMonitor.lastTick,
                                receivedAt: watchMonitor.lastTickReceivedAt,
                                importMessage: watchMonitor.lastImportMessage,
                                connectionStatus: watchMonitor.connectionStatus
                            )
                        }
                    }

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

    /// A Watch session is "live" when a tick has arrived and it's recent
    /// enough that a set is plausibly still in progress.
    private func isLiveSessionActive(at now: Date) -> Bool {
        guard watchMonitor.lastTick != nil, let receivedAt = watchMonitor.lastTickReceivedAt else {
            return false
        }
        return now.timeIntervalSince(receivedAt) <= Self.liveSessionWindow
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

#Preview("Watch session live") {
    let monitor = PhoneWatchSessionMonitor.shared
    monitor.lastTick = LiveTickEnvelope(repCount: 4, currentVelocityMS: 0.38, heartRateBPM: 138, elapsedSeconds: 24)
    monitor.lastTickReceivedAt = .now
    monitor.lastImportMessage = "Last import: Bench Press · 5 reps"

    return TodayView()
        .modelContainer(PreviewSeed.seededContainer())
}

#Preview("Watch session idle") {
    let monitor = PhoneWatchSessionMonitor.shared
    monitor.lastTick = nil
    monitor.lastTickReceivedAt = nil

    return TodayView()
        .modelContainer(PreviewSeed.seededContainer())
}
