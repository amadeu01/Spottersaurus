//
//  SetLifecycleController.swift
//  SpottersaurusKit
//
//  The pure, platform-neutral state machine that sequences one working set:
//  arm → reps → auto-rack (motion settle) → rest → next (see docs/PLAN.md,
//  "Watch app / Session lifecycle"). This is the logic layer the watchOS
//  session engine (Phase 4a/4b, hardware) drives; it takes already-parsed
//  high-level inputs (arm/rep/rack/rest-tick/SpotEvent) and never touches
//  CoreMotion, HealthKit, SwiftUI, or WorkoutKit. Time is always injected —
//  no wall-clock — so the whole machine is deterministic and unit-testable.
//

import Foundation

/// The main lifecycle state of a working set, in PLAN vocabulary.
public enum SetLifecycleState: Sendable, Equatable {
    case idle
    case armed
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

    /// Arms the next working set. Valid from `.idle` (first set) or
    /// `.complete` (the previous set finished its rest); resets rep count and
    /// any lingering alert. Ignored from any other state.
    public mutating func arm() {
        guard state == .idle || state == .complete else { return }
        state = .armed
        repCount = 0
        alertStage = .none
    }

    /// A completed rep, reported by the RepSegmenter-driven session engine.
    /// Valid from `.armed` (the first rep of the set) or `.repping`
    /// (subsequent reps); ignored otherwise (e.g. a stray rep while idle).
    public mutating func repCompleted() {
        guard state == .armed || state == .repping else { return }
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
