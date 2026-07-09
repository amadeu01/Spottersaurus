import SwiftUI
import SpottersaurusKit

/// Root screen: renders the day's Live Session off
/// `WatchPlannedSessionStore.shared.cursor` (M1b) instead of a single
/// hardcoded set. Reads the store directly (not through a
/// `WatchDependencies` closure) so SwiftUI's `@Observable` tracking picks up
/// cursor changes reactively, mirroring how `LiveSetView` already reads
/// `sessionStore.connectionStatus`.
struct WatchRootView: View {
    @Environment(\.watchDependencies) private var dependencies
    @State private var sessionStore = WatchPlannedSessionStore.shared

    /// What the root should show for the current cursor. `Equatable` so
    /// `.onChange` can detect the "session just finished" transition and
    /// fire the Live Set Lifecycle `.ended` event exactly once.
    private enum ScreenState: Equatable {
        case noSession
        case runningSet(current: PlannedSetEnvelope, setIndex: Int, setCount: Int, nextSet: PlannedSetEnvelope?)
        case sessionComplete(setCount: Int)
    }

    private var screenState: ScreenState {
        guard let cursor = sessionStore.cursor else { return .noSession }
        if let current = cursor.current {
            return .runningSet(current: current, setIndex: cursor.setIndex, setCount: cursor.setCount, nextSet: cursor.next)
        }
        // `setCount == 0` means a session was received but had no sets —
        // treated the same as "no session" (no fallback, per the cursor's
        // own doc comment). `setCount > 0` means every set ran to
        // completion — a real "session complete" summary.
        guard cursor.setCount > 0 else { return .noSession }
        return .sessionComplete(setCount: cursor.setCount)
    }

    var body: some View {
        Group {
            switch screenState {
            case .noSession:
                NoPlannedSessionView()
            case .runningSet(let current, let setIndex, let setCount, let nextSet):
                LiveSetView(
                    plannedSet: current,
                    setIndex: setIndex,
                    setCount: setCount,
                    nextSet: nextSet,
                    onSetSessionComplete: {
                        dependencies.advanceSessionCursor()
                    }
                )
                .id(current.id)
            case .sessionComplete(let setCount):
                SessionCompleteView(setCount: setCount)
            }
        }
        .onChange(of: screenState) { oldValue, newValue in
            // The whole Live Session just finished (last set's rest ran
            // out and the cursor advanced past it) — fire the session-level
            // `.ended` lifecycle event exactly once for this transition.
            if case .runningSet = oldValue, case .sessionComplete = newValue {
                dependencies.sendLifecycle(.ended)
            }
        }
        .onDisappear {
            // "User stops" mid-session: the app is going away while a set/
            // rest was still in progress, not because it finished normally.
            if case .runningSet = screenState {
                dependencies.sendLifecycle(.ended)
            }
        }
    }
}

#Preview("No session") {
    WatchPlannedSessionStore.shared.debugSeedCursor(nil)
    return WatchRootView()
}

#Preview("Mid-session (set 2 of 4)") {
    var cursor = PlannedSessionCursor(sets: [
        .init(lift: .squat, exerciseName: "Back Squat", targetReps: 5, weightKg: 140, restSeconds: 180, sortIndex: 0),
        .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 150, sortIndex: 1),
        .init(lift: .deadlift, exerciseName: "Deadlift", targetReps: 3, weightKg: 180, restSeconds: 210, sortIndex: 2),
        .init(lift: .accessory, exerciseName: "Row", targetReps: 10, weightKg: 40, restSeconds: 90, sortIndex: 3)
    ])
    cursor.advance()
    WatchPlannedSessionStore.shared.debugSeedCursor(cursor)
    return WatchRootView()
}

#Preview("Session complete") {
    var cursor = PlannedSessionCursor(sets: [
        .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 150, sortIndex: 0)
    ])
    cursor.advance()
    WatchPlannedSessionStore.shared.debugSeedCursor(cursor)
    return WatchRootView()
}
