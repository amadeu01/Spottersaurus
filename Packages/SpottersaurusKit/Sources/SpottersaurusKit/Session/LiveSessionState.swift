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

    /// The short window within which a sequenced tick/heartbeat (ADR 0001's
    /// ~2 s heartbeat) must have arrived for the link to read as `.live`
    /// (ADR 0003, "Liveness = heartbeat, not raw reachability"). Set to 3x
    /// the heartbeat cadence so a single missed beat can't flip the status —
    /// only a sustained gap does. This is a *different, much shorter* axis
    /// than `staleTimeout`: `staleTimeout` decides whether the whole Live
    /// Session should be torn down; `heartbeatWindow` decides whether the
    /// *link* momentarily looks quiet while the session obviously continues.
    public static let heartbeatWindow: TimeInterval = 6

    /// Heartbeat-recency liveness of the Watch↔iPhone link (ADR 0003),
    /// distinct from `ConnectionStatus` (pairing/reachability — "can we
    /// reach the Watch at all") and from `isStale`/`phase` (session
    /// lifecycle — "has this session ended"). This axis answers a narrower
    /// question: "is data actually flowing right now". A brief reachability
    /// blip reads as `.reconnecting`, not a drop, and self-heals back to
    /// `.live` the moment a fresh tick/heartbeat arrives — it never latches.
    public enum LiveLinkStatus: Sendable, Equatable, CaseIterable {
        /// A tick/heartbeat/lifecycle event arrived within `heartbeatWindow`
        /// of `now` — the link looks healthy.
        case live
        /// Quiet longer than `heartbeatWindow` but still under `staleTimeout`
        /// — probably a brief foreground/background or radio blip; the
        /// session is still considered active, but the UI should show
        /// "reconnecting" rather than the last-known metrics as gospel.
        case reconnecting
        /// Quiet at or beyond `staleTimeout` — same threshold `isStale` uses;
        /// the session is effectively dead.
        case stale
    }

    /// Pure derivation of `LiveLinkStatus` from the timestamp of the most
    /// recently folded tick/lifecycle event (`lastEventAt`) and an injected
    /// `now` — no timers, no wall-clock reads. A session that has never
    /// folded any event (`lastEventAt == nil`) has nothing to call "live",
    /// so it reads as `.stale`.
    public func linkStatus(
        at now: Date,
        heartbeatWindow: TimeInterval = LiveSessionState.heartbeatWindow,
        staleTimeout: TimeInterval = LiveSessionState.staleTimeout
    ) -> LiveLinkStatus {
        guard let lastEventAt else { return .stale }
        let age = now.timeIntervalSince(lastEventAt)
        if age < heartbeatWindow { return .live }
        if age < staleTimeout { return .reconnecting }
        return .stale
    }

    public private(set) var phase: Phase = .idle
    public private(set) var identity: Identity?
    public private(set) var metrics: Metrics?
    /// Wall-clock time (injected, never read internally) of the most
    /// recently folded event — armed, tick, or ended. Backs the staleness
    /// check; `nil` means no event has ever been folded.
    public private(set) var lastEventAt: Date?

    /// High-water mark of the most recently *folded* event's `sequence`
    /// (ADR 0004: `docs/adr/0004-offline-reconcile-and-calibration-
    /// persistence.md`). **Assumption**: ticks and Live Set Lifecycle Events
    /// share a single monotonic counter, because one Watch produces both
    /// streams for a session — so one high-water mark, not two, is enough
    /// to gate either stream's deliveries idempotently.
    ///
    /// `sequence == 0` is the legacy/unstamped sentinel (pre-ADR-0004
    /// payloads default to 0 via `decodeIfPresent(...) ?? 0`). A real
    /// sequenced stream always starts at 1, so 0 never collides with a
    /// legitimate first event — `0`-stamped events skip the idempotency gate
    /// entirely (see `shouldFold(sequence:)`) and keep today's
    /// last-writer-wins behavior, rather than being compared against a
    /// high-water mark that may belong to an entirely different (real)
    /// stream.
    public private(set) var lastSequence: Int = 0

    public init() {}

    /// Whether an incoming event stamped `sequence` should be folded.
    /// Legacy/unstamped events (`sequence == 0`) always fold. A real
    /// (`> 0`) sequence folds only if strictly newer than the last one
    /// folded — duplicates and out-of-order stragglers (the basis for
    /// gap-tolerant reconnect: a resend after a dropped link can't rewind
    /// state) are dropped, leaving state unchanged.
    private func shouldFold(sequence: Int) -> Bool {
        guard sequence > 0 else { return true }
        return sequence > lastSequence
    }

    /// Advances the high-water mark after folding — a no-op for
    /// legacy/unstamped (`0`) events, which never move the mark.
    private mutating func markFolded(sequence: Int) {
        guard sequence > 0 else { return }
        lastSequence = max(lastSequence, sequence)
    }

    /// Folds a Live Set Lifecycle Event (`armed`/`ended`) into the session
    /// state. `armed` starts (from `.idle`) or replaces (mid-session, e.g.
    /// the next set) the current set identity and moves the phase to
    /// `.active` — a fresh `armed` never resets to `.idle` first, so the
    /// session stays live across sets. `ended` moves the phase to `.ended`
    /// (see the `Phase.resting` doc comment for why this doesn't yet
    /// distinguish "one set of many ended" from "the whole session ended").
    ///
    /// Idempotency gate (ADR 0004): a stale/duplicate/out-of-order event
    /// (per `shouldFold(sequence:)`) is ignored outright — state, including
    /// `lastEventAt`, is left completely unchanged.
    public mutating func reduce(lifecycle event: LiveSetLifecycleEnvelope, now: Date) {
        guard shouldFold(sequence: event.sequence) else { return }
        switch event {
        case let .armed(lift, targetReps, weightKg, setIndex, setCount, _):
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
        markFolded(sequence: event.sequence)
        lastEventAt = now
    }

    /// Folds a running `LiveTickEnvelope` into the session state, replacing
    /// the previous metrics wholesale (each tick is a full snapshot, not a
    /// delta). Updates the metrics regardless of phase — a stray tick after
    /// `ended` is simply the latest-known reading, harmless to record — but
    /// does not itself change `phase` (only lifecycle events do).
    ///
    /// Idempotency gate (ADR 0004): a stale/duplicate/out-of-order tick (per
    /// `shouldFold(sequence:)`) is ignored outright — state, including
    /// `lastEventAt`, is left completely unchanged.
    public mutating func reduce(tick: LiveTickEnvelope, now: Date) {
        guard shouldFold(sequence: tick.sequence) else { return }
        metrics = Metrics(
            repCount: tick.repCount,
            meanConcentricVelocityMS: tick.currentVelocityMS,
            heartRateBPM: tick.heartRateBPM,
            alertStage: tick.alertStage,
            elapsedSeconds: tick.elapsedSeconds,
            setIndex: tick.setIndex,
            setCount: tick.setCount
        )
        markFolded(sequence: tick.sequence)
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
