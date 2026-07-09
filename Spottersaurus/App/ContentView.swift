import SwiftData
import SwiftUI
import SpottersaurusKit

struct ContentView: View {
    let storeTier: StoreTier

    @State private var showSplash = true
    @State private var monitor = LiveSessionMonitor.shared
    /// The lifter explicitly closed the In-Workout takeover for the
    /// *current* Live Session. Reset (not permanently suppressed) whenever a
    /// fresh Live Session starts, so a dismiss never carries over to the
    /// next set — see `onChange(of:)` below.
    @State private var dismissedInWorkout = false

    init(storeTier: StoreTier = .local) {
        self.storeTier = storeTier
    }

    /// Phases in which the Live Session is running and the In-Workout View
    /// (or its "return to set" pill) is relevant to show.
    private static func isLive(_ phase: LiveSessionState.Phase) -> Bool {
        phase == .armed || phase == .active || phase == .resting
    }

    private var isLiveSessionPresentable: Bool {
        Self.isLive(monitor.state.phase)
    }

    private var inWorkoutPresented: Binding<Bool> {
        Binding(
            get: { isLiveSessionPresentable && !dismissedInWorkout },
            set: { newValue in
                if !newValue { dismissedInWorkout = true }
            }
        )
    }

    private var returnPillLabel: String {
        guard let identity = monitor.state.identity else { return "Live set in progress" }
        return "Set \(identity.setIndex + 1) of \(identity.setCount) · \(identity.lift.displayName)"
    }

    var body: some View {
        ZStack {
            PlannerTabsView()
            if showSplash {
                SplashView { showSplash = false }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .overlay(alignment: .top) {
            StoreHealthBanner(storeTier: storeTier)
        }
        .overlay(alignment: .bottom) {
            if dismissedInWorkout, isLiveSessionPresentable {
                ReturnToSetPill(setLabel: returnPillLabel, alertStage: monitor.state.metrics?.alertStage ?? .none) {
                    dismissedInWorkout = false
                }
            }
        }
        .fullScreenCover(isPresented: inWorkoutPresented) {
            InWorkoutView(
                phase: monitor.state.phase,
                identity: monitor.state.identity,
                metrics: monitor.state.metrics
            ) {
                dismissedInWorkout = true
            }
        }
        .onChange(of: monitor.state.phase) { previous, current in
            // A fresh Live Session started (idle/ended -> armed/active) —
            // never let a manual dismiss from a *previous* session suppress
            // the takeover for this new one.
            if Self.isLive(current), !Self.isLive(previous) {
                dismissedInWorkout = false
            }
        }
    }
}

#Preview("Idle — no takeover") {
    // `LiveSessionMonitor.shared` starts `.idle` and is left untouched here,
    // so the In-Workout `.fullScreenCover` never presents.
    ContentView()
        .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}

#Preview("Active — takeover presented") {
    // NOTE: `LiveSessionMonitor.shared` is a process-wide singleton (same
    // caveat as `PhoneWatchSessionMonitor.shared` elsewhere in this file's
    // sibling previews) — seeding it here folds real lifecycle/tick events
    // through the same public reducer entry points production call sites
    // use, rather than poking at private state.
    LiveSessionMonitor.shared.receive(lifecycle: .armed(lift: .bench, targetReps: 5, weightKg: 100, setIndex: 1, setCount: 4))
    LiveSessionMonitor.shared.receive(tick: LiveTickEnvelope(
        repCount: 2,
        currentVelocityMS: 0.4,
        heartRateBPM: 128,
        elapsedSeconds: 12,
        alertStage: .none,
        setIndex: 1,
        setCount: 4
    ))

    return ContentView()
        .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
