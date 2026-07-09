import Combine
import Foundation
import Observation
import SpottersaurusKit

/// iOS wrapper around the pure `LiveSessionState` reducer (Phase 0.2, L3):
/// owns the wall-clock-driven glue (feeding Watch → iPhone lifecycle events
/// + ticks in, running the 5-minute staleness timeout) while all the actual
/// state-folding logic lives in `LiveSessionState` (SpottersaurusKit),
/// fully unit-tested there with injected time. This is the deterministic
/// replacement for the old tick-recency heuristic
/// (`PhoneWatchSessionMonitor.lastTickReceivedAt` age-guessing) — every
/// live iPhone surface (S1 In-Workout View, R3 Today card, S2 Live
/// Activity, all later tasks) is meant to read `state` here rather than
/// re-derive liveness from tick ages.
///
/// `PhoneWatchSessionMonitor` is untouched and still drives the WCSession
/// connection chip (D1/D2) — this is an additional, session-scoped source
/// of truth alongside it, not a replacement for it.
@MainActor
@Observable
final class LiveSessionMonitor {
    static let shared = LiveSessionMonitor()

    /// How often the staleness timer re-checks the current state against
    /// `LiveSessionState.staleTimeout` (5 min). Deliberately much shorter
    /// than the timeout itself so a torn-down session is never more than a
    /// few seconds late; a `Timer.publish` matches the existing
    /// `LiveSetView` convention for wall-clock ticks in this codebase.
    private static let stalenessPollInterval: TimeInterval = 15

    private(set) var state = LiveSessionState()
    private var stalenessCancellable: AnyCancellable?

    private init() {
        stalenessCancellable = Timer.publish(every: Self.stalenessPollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.checkStaleness(now: now)
            }
    }

    /// Folds a Live Set Lifecycle Event (`armed`/`ended`) received from the
    /// Watch. `now` is injectable for tests; production call sites use the
    /// default wall clock.
    func receive(lifecycle event: LiveSetLifecycleEnvelope, now: Date = Date()) {
        state.reduce(lifecycle: event, now: now)
    }

    /// Folds a running `LiveTickEnvelope` received from the Watch.
    func receive(tick: LiveTickEnvelope, now: Date = Date()) {
        state.reduce(tick: tick, now: now)
    }

    /// Runs the pure staleness check/transition against the current wall
    /// clock. Exposed (not just internal to the timer) so a view can also
    /// invoke this eagerly — e.g. on becoming active/foreground — without
    /// waiting for the next timer fire.
    func checkStaleness(now: Date = Date()) {
        state.applyStalenessIfNeeded(at: now)
    }
}
