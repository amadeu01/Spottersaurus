//
//  LiveSessionState.swift
//  SpottersaurusKit
//
//  The pure, platform-neutral model of a **Live Session** on the iPhone side
//  (see CONTEXT.md glossary + ADR 0001,
//  `docs/adr/0001-live-session-surfaces-and-transport.md`): the in-progress
//  execution of a Planned Session on the Watch, from the first Live Set
//  armed to session end. This replaces the old tick-recency heuristic
//  (`PhoneWatchSessionMonitor.lastTickReceivedAt` age-guessing) with a
//  deterministic state machine folded from the Watch's explicit
//  `LiveSetLifecycleEnvelope` events (`armed`/`ended`) plus the running
//  `LiveTickEnvelope` metric stream (Phase 0.2, L1). Every iPhone live
//  surface (S1 In-Workout View, R3 Today card, S2 Live Activity) is meant to
//  read this type rather than re-deriving session liveness from tick ages.
//
//  Pure value type: no timers, no WCSession, no wall-clock reads inside —
//  every reducer takes `now` as an explicit parameter so the whole machine
//  is deterministic and unit-testable (mirrors `SetLifecycleController`'s
//  injected-time discipline).
//

import Foundation

/// Session-scoped state of a Live Session, folded from Watch→iPhone
/// lifecycle events and ticks.
public struct LiveSessionState: Sendable, Equatable {

    /// The Live Session's coarse phase. Kept intentionally small — just what
    /// S1/R3/S2 need to decide what to render.
    ///
    /// Design note on `armed` vs `active`, and on `resting`: the current wire
    /// vocabulary (L1) only has two lifecycle events — `armed` and `ended` —
    /// plus the tick stream. There is no meaningful "armed, zero reps yet"
    /// surface distinct from "live and in progress": the moment the Watch
    /// arms a set the wearer is about to (or already) lifting, so `armed`
    /// folds straight to `.active` (see `reduce(lifecycle:now:)`). `.armed`
    /// is kept in this enum for API completeness / a future surface that
    /// wants to show a brief "get ready" beat, but the current reducer never
    /// produces it. Similarly, `ended` carries no payload telling us whether
    /// more sets remain in the Live Session (that would require either a
    /// richer `ended` payload or comparing against the *next* `armed`, which
    /// hasn't happened yet) — so today `ended` always folds to `.ended`,
    /// full stop. `.resting` is reserved for a later task (M1/S1) that adds
    /// that information; until then a "between sets" UI can treat `.ended`
    /// followed by a fresh `armed` as the resting→active transition it
    /// actually observes.
    public enum Phase: Sendable, Equatable, CaseIterable {
        case idle
        case armed
        case active
        case resting
        case ended
    }

    /// The current set's identity, taken from the most recently received
    /// `armed` lifecycle event.
    public struct Identity: Sendable, Equatable {
        public var lift: LiftKind
        public var targetReps: Int
        public var weightKg: Double
        /// Zero-based position of this set within the Live Session.
        public var setIndex: Int
        /// Total number of sets in the Live Session.
        public var setCount: Int

        public init(lift: LiftKind, targetReps: Int, weightKg: Double, setIndex: Int, setCount: Int) {
            self.lift = lift
            self.targetReps = targetReps
            self.weightKg = weightKg
            self.setIndex = setIndex
            self.setCount = setCount
        }
    }

    /// The latest running metrics, taken from the most recently received
    /// `LiveTickEnvelope`.
    public struct Metrics: Sendable, Equatable {
        public var repCount: Int
        /// The VBT headline metric (ADR 0001's Mean Concentric Velocity),
        /// mirrored unmodified from `LiveTickEnvelope.currentVelocityMS`.
        public var meanConcentricVelocityMS: Double
        public var heartRateBPM: Double
        public var alertStage: AlertStage
        public var elapsedSeconds: TimeInterval
        /// Zero-based position of the set this tick belongs to.
        public var setIndex: Int
        /// Total number of sets in the Live Session.
        public var setCount: Int

        public init(
            repCount: Int,
            meanConcentricVelocityMS: Double,
            heartRateBPM: Double,
            alertStage: AlertStage,
            elapsedSeconds: TimeInterval,
            setIndex: Int,
            setCount: Int
        ) {
            self.repCount = repCount
            self.meanConcentricVelocityMS = meanConcentricVelocityMS
            self.heartRateBPM = heartRateBPM
            self.alertStage = alertStage
            self.elapsedSeconds = elapsedSeconds
            self.setIndex = setIndex
            self.setCount = setCount
        }
    }

    /// A Live Session with no event for this long is treated as ended even
    /// without an explicit `ended` — the grill-decided 5-minute staleness
    /// timeout (ADR 0001 / CONTEXT.md "Live Session").
    public static let staleTimeout: TimeInterval = 5 * 60

    public private(set) var phase: Phase = .idle
    public private(set) var identity: Identity?
    public private(set) var metrics: Metrics?
    /// Wall-clock time (injected, never read internally) of the most
    /// recently folded event — armed, tick, or ended. Backs the staleness
    /// check; `nil` means no event has ever been folded.
    public private(set) var lastEventAt: Date?

    public init() {}

    /// Folds a Live Set Lifecycle Event (`armed`/`ended`) into the session
    /// state. `armed` starts (from `.idle`) or replaces (mid-session, e.g.
    /// the next set) the current set identity and moves the phase to
    /// `.active` — a fresh `armed` never resets to `.idle` first, so the
    /// session stays live across sets. `ended` moves the phase to `.ended`
    /// (see the `Phase.resting` doc comment for why this doesn't yet
    /// distinguish "one set of many ended" from "the whole session ended").
    public mutating func reduce(lifecycle event: LiveSetLifecycleEnvelope, now: Date) {
        switch event {
        case let .armed(lift, targetReps, weightKg, setIndex, setCount):
            identity = Identity(
                lift: lift,
                targetReps: targetReps,
                weightKg: weightKg,
                setIndex: setIndex,
                setCount: setCount
            )
            phase = .active
        case .ended:
            phase = .ended
        }
        lastEventAt = now
    }

    /// Folds a running `LiveTickEnvelope` into the session state, replacing
    /// the previous metrics wholesale (each tick is a full snapshot, not a
    /// delta). Updates the metrics regardless of phase — a stray tick after
    /// `ended` is simply the latest-known reading, harmless to record — but
    /// does not itself change `phase` (only lifecycle events do).
    public mutating func reduce(tick: LiveTickEnvelope, now: Date) {
        metrics = Metrics(
            repCount: tick.repCount,
            meanConcentricVelocityMS: tick.currentVelocityMS,
            heartRateBPM: tick.heartRateBPM,
            alertStage: tick.alertStage,
            elapsedSeconds: tick.elapsedSeconds,
            setIndex: tick.setIndex,
            setCount: tick.setCount
        )
        lastEventAt = now
    }

    /// Whether this session should be considered stale (no lifecycle event
    /// or tick for `timeout`) as of `now`. Pure — `now` is always injected.
    /// A session that's already `.idle` (nothing ever happened) or `.ended`
    /// (already torn down) is never "stale" — there's nothing left to time
    /// out.
    public func isStale(at now: Date, timeout: TimeInterval = LiveSessionState.staleTimeout) -> Bool {
        guard phase != .idle, phase != .ended, let lastEventAt else { return false }
        return now.timeIntervalSince(lastEventAt) >= timeout
    }

    /// Ends the session if it's gone stale as of `now` — the pure half of
    /// the staleness timeout (surfaces tear down when `phase` becomes
    /// `.ended`). No-ops when not stale, so callers can invoke this on
    /// every timer tick without side effects. `LiveSessionMonitor` (the
    /// `@Observable` iOS wrapper) is what actually triggers this on a
    /// wall-clock timer; this type itself never reads the clock.
    public mutating func applyStalenessIfNeeded(at now: Date, timeout: TimeInterval = LiveSessionState.staleTimeout) {
        guard isStale(at: now, timeout: timeout) else { return }
        phase = .ended
    }
}
