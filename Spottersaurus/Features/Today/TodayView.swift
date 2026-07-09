import SwiftData
import SwiftUI
import SpottersaurusKit

struct TodayView: View {
    @Environment(\.plannerDependencies) private var dependencies
    @Query private var programs: [Program]
    @Query private var maxes: [UserMaxes]
    @State private var viewModel = TodayViewModel()
    @State private var watchMonitor = PhoneWatchSessionMonitor.shared
    @State private var liveSessionMonitor = LiveSessionMonitor.shared
    @State private var isPresentingOverrideEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    WatchConnectionChip(status: watchMonitor.connectionStatus)

                    // Live metrics moved to S1's app-wide In-Workout takeover
                    // (`InWorkoutView`); this compact card only ever surfaces
                    // the idle/disconnected case with a reconnect affordance,
                    // so it never competes with that takeover.
                    if showsReconnectCard {
                        WatchReconnectCard(status: watchMonitor.connectionStatus) {
                            WatchLink.shared.reactivate()
                        }
                    }

                    if let program = viewModel.activeProgram(from: programs),
                       let day = viewModel.todaysProgramDay(in: program) {
                        // Tapping the card opens the ephemeral Session
                        // Override editor (Phase 0.2 M2) so the lifter can
                        // autoregulate today's loads/reps by feel before
                        // sending — this never mutates `program`/`day`. The
                        // button below stays a direct "send as planned" path.
                        Button {
                            isPresentingOverrideEditor = true
                        } label: {
                            TodaySessionCard(program: program, day: day, maxes: maxes)
                        }
                        .buttonStyle(.plain)

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
            .sheet(isPresented: $isPresentingOverrideEditor) {
                if let program = viewModel.activeProgram(from: programs),
                   let day = viewModel.todaysProgramDay(in: program) {
                    SessionOverrideEditorView(program: program, day: day, maxes: maxes)
                }
            }
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

    /// The reconnect card only ever surfaces the idle/disconnected case: it
    /// hides while a Live Session is active/armed/resting (S1's app-wide
    /// `InWorkoutView` owns that surface) and while the Watch is already
    /// `.connected` (the header chip already covers that calmly, without a
    /// second card restating it).
    private var showsReconnectCard: Bool {
        guard watchMonitor.connectionStatus != .connected else { return false }
        switch liveSessionMonitor.state.phase {
        case .idle, .ended: return true
        case .armed, .active, .resting: return false
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

#Preview("Watch unreachable — reconnect card") {
    // No Live Session in progress, Watch paired/installed but unreachable ->
    // the reconnect card should render with its retry button.
    PhoneWatchSessionMonitor.shared.updateSessionState(
        isPaired: true,
        isWatchAppInstalled: true,
        isReachable: false,
        activationState: ConnectionStatus.activatedRawValue
    )

    return TodayView()
        .modelContainer(PreviewSeed.seededContainer())
}

#Preview("Live session active — reconnect card hidden") {
    // NOTE: both monitors are process-wide singletons (same caveat as
    // sibling previews in this file/`ContentView`) — seeded via their public
    // reducer entry points. Even though the Watch reports unreachable here,
    // an active Live Session hides the reconnect card so it never competes
    // with S1's `InWorkoutView` takeover.
    PhoneWatchSessionMonitor.shared.updateSessionState(
        isPaired: true,
        isWatchAppInstalled: true,
        isReachable: false,
        activationState: ConnectionStatus.activatedRawValue
    )
    LiveSessionMonitor.shared.receive(lifecycle: .armed(lift: .bench, targetReps: 5, weightKg: 100, setIndex: 1, setCount: 4))

    return TodayView()
        .modelContainer(PreviewSeed.seededContainer())
}
