//
//  SetLifecycleController.swift
//  SpottersaurusKit
//
//  The pure, platform-neutral state machine that sequences one working set:
//  arm → settle (unrack/walkout/brace) → reps → auto-rack (motion settle) →
//  rest → next (see docs/PLAN.md, "Watch app / Session lifecycle", and
//  docs/adr/0006-unrack-setup-phase.md). This is the logic layer the watchOS
//  session engine (Phase 4a/4b, hardware) drives; it takes already-parsed
//  high-level inputs (arm/rep/rack/rest-tick/SpotEvent) and never touches
//  CoreMotion, HealthKit, SwiftUI, or WorkoutKit. Time is always injected —
//  no wall-clock — so the whole machine is deterministic and unit-testable.
//

import Foundation

/// The main lifecycle state of a working set, in PLAN vocabulary.
public enum SetLifecycleState: Sendable, Equatable {
    case idle
    /// Start has been pressed: the lifter is unracking / walking out / lifting
    /// off / bracing. Real motion, but not a rep (ADR 0006 — "Unrack / setup
    /// phase before rep detection"). There is no separate hands-free "I'm set"
    /// press (by the time the lifter is braced, hands are already locked on
    /// the bar), so `arm()` lands directly here rather than in a distinct
    /// "armed, setup not yet begun" state that nothing would ever observe —
    /// keeping a state around that's never independently true would make the
    /// machine dishonest about what's actually detectable. The `RepSegmenter`
    /// (P15-D2) gates the first rep on the lift-appropriate pattern upstream
    /// (squat/bench: first eccentric→concentric excursion; deadlift: first
    /// sustained concentric-from-rest excursion); this controller only needs
    /// to know that the first `repCompleted()` call is the signal setup is
    /// over — it stays a pure reducer with no timers of its own.
    case settling
    case repping
    case racked
    case resting
    case complete
}

/// The escalation sub-state driven by `SpotEngine` events. Independent of the
/// main lifecycle so a grind/rack-it alert never derails rep counting.
/// `Codable` so it can ride on the Watch -> iPhone `LiveTickEnvelope` wire
/// format (see `Sync/SessionEnvelope.swift`) without a parallel enum.
public enum AlertStage: Sendable, Equatable, Codable {
    case none
    case grinding
    case rackIt
}

/// Sequences one working set from arm through rest, driven entirely by
/// injected inputs and injected elapsed time.
public struct SetLifecycleController: Sendable, Equatable {
    /// Target rest duration (s) between sets; `restTick` compares injected
    /// elapsed time against this to decide when the rest is over.
    public var restSeconds: TimeInterval

    public private(set) var state: SetLifecycleState = .idle
    public private(set) var repCount: Int = 0
    public private(set) var alertStage: AlertStage = .none

    public init(restSeconds: TimeInterval = 90) {
        self.restSeconds = restSeconds
    }

    /// Arms the next working set — the lifter has pressed Start and is now
    /// unracking/walking out/bracing (ADR 0006). Valid from `.idle` (first
    /// set) or `.complete` (the previous set finished its rest); resets rep
    /// count and any lingering alert. Ignored from any other state. Lands in
    /// `.settling`, not `.repping`: motion during setup must not be counted
    /// as reps (the segmenter's per-lift rep-1 gate, P15-D2, is what makes
    /// that motion safe to observe upstream at all).
    public mutating func arm() {
        guard state == .idle || state == .complete else { return }
        state = .settling
        repCount = 0
        alertStage = .none
    }

    /// A completed rep, reported by the RepSegmenter-driven session engine.
    /// Valid from `.settling` (the segmenter's gated first rep — setup is
    /// over, this is rep 1) or `.repping` (subsequent reps); ignored
    /// otherwise (e.g. a stray rep while idle).
    public mutating func repCompleted() {
        guard state == .settling || state == .repping else { return }
        repCount += 1
        state = .repping
    }

    /// The bar-motion-settle signal (computed upstream, not here): the bar has
    /// come to rest after the working set's last rep. Valid only from
    /// `.repping`; ignored otherwise. Belt-and-suspenders: once the bar is
    /// racked the danger is over, so any lingering alert clears automatically
    /// here too, rather than depending on the lifter tapping Resolved (see
    /// docs/backlog.md P1-1b).
    public mutating func autoRack() {
        guard state == .repping else { return }
        state = .racked
        alertStage = .none
    }

    /// A rest-timer tick / elapsed reading, injected by the caller (never a
    /// wall-clock read here). The first tick after `autoRack()` starts the
    /// rest clock (`.racked` → `.resting`); subsequent ticks while resting
    /// just report progress.
    public mutating func restTick(elapsed: TimeInterval) {
        switch state {
        case .racked:
            state = .resting
        case .resting:
            break
        default:
            return
        }
        if elapsed >= restSeconds {
            state = .complete
        }
    }

    /// Surfaces a `SpotEngine` event as the alert sub-state. Independent of
    /// the main lifecycle: escalation never touches `state` or `repCount`, so
    /// a grind/rack-it/resolve sequence can play out mid-rep without derailing
    /// counting. Raising an alert (`.grinding`/`.rackIt`) is only meaningful
    /// while a rep is actually in flight. Clearing one (`.resolved`) must work
    /// from any state: once the bar is racked the lifecycle can move on to
    /// `.resting`/`.complete` before the spot engine reports resolution, and a
    /// stuck `.rackIt` alert must never survive past that point (see
    /// docs/backlog.md P1-1a — a lifter must always be able to clear it).
    public mutating func handle(spotEvent: SpotEvent) {
        switch spotEvent.kind {
        case .grinding:
            guard state == .repping else { return }
            alertStage = .grinding
        case .rackIt:
            guard state == .repping else { return }
            alertStage = .rackIt
        case .resolved:
            alertStage = .none
        }
    }
}
