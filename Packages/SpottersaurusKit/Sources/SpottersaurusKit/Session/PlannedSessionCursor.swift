//
//  PlannedSessionCursor.swift
//  SpottersaurusKit
//
//  Pure, platform-neutral cursor over a `PlannedSessionEnvelope`'s ordered
//  sets (see `Sync/SessionEnvelope.swift`). This is the fix for the
//  "everything is bench" bug: the Watch used to read only
//  `PlannedSessionEnvelope.firstSet` (falling back to a hardcoded bench @
//  100 kg when no session had been sent) instead of progressing through the
//  whole day. This type owns none of that wiring — it just models "where are
//  we in this list of sets" as a value, so the Watch executor (M1b) and its
//  tests can reason about advancement without any WCSession/WorkoutKit/
//  SwiftUI dependency.
//
//  Advancing past the last set is well-defined rather than a crash/UB: the
//  cursor's index simply clamps at `setCount`, at which point `current` is
//  `nil` and `isFinished` is `true` — this is the "all sets done" signal
//  M1b uses to emit the Live Set Lifecycle `ended` event for the whole
//  session (see `LiveSetLifecycleEnvelope` + ADR 0001). A session with no
//  sets at all starts already `isFinished` (there is nothing to run) with
//  `current == nil` and `setCount == 0` — the honest "no session" empty
//  state has no bench/weight fallback anywhere in this type.
//

import Foundation

/// A cursor over one `PlannedSessionEnvelope`'s ordered `PlannedSetEnvelope`s,
/// tracking which set is currently "up" as the Watch progresses through a
/// Live Session. Value-semantic and pure: no timers, no I/O, no wall-clock —
/// advancement is driven entirely by the caller (e.g. on manual re-arm after
/// a rack/rest).
public struct PlannedSessionCursor: Sendable, Equatable {
    /// Sets ordered by `PlannedSetEnvelope.sortIndex` (ascending), regardless
    /// of the order they were supplied in.
    public let orderedSets: [PlannedSetEnvelope]

    /// 0-based index of the current set. Ranges `0...setCount`; the value
    /// `setCount` (only reachable via `advance()` from the last set, or as
    /// the starting value when `setCount == 0`) means "no current set" —
    /// see `isFinished`.
    public private(set) var setIndex: Int = 0

    /// Builds a cursor from an already-extracted array of sets, sorting them
    /// by `sortIndex` so callers never need to pre-sort.
    public init(sets: [PlannedSetEnvelope]) {
        self.orderedSets = sets.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Builds a cursor over a full planned session's sets.
    public init(session: PlannedSessionEnvelope) {
        self.init(sets: session.sets)
    }

    /// Total number of sets in the session (the "M" in "Set N of M").
    public var setCount: Int { orderedSets.count }

    /// The set currently up. `nil` when the session has no sets, or once
    /// `advance()` has moved past the last one (`isFinished`). There is no
    /// fallback set — callers must handle `nil` as an honest empty state.
    public var current: PlannedSetEnvelope? {
        guard setIndex < orderedSets.count else { return nil }
        return orderedSets[setIndex]
    }

    /// The set after `current`, if any. `nil` when `current` is the last
    /// set (or when there is no current set at all).
    public var next: PlannedSetEnvelope? {
        let upcomingIndex = setIndex + 1
        guard upcomingIndex < orderedSets.count else { return nil }
        return orderedSets[upcomingIndex]
    }

    /// Whether there is a set after `current` to advance into.
    public var hasNext: Bool { setIndex + 1 < orderedSets.count }

    /// Whether `current` is the final set of the session (true only while
    /// there IS a current set — an already-finished or empty cursor is not
    /// "the last set", it's finished).
    public var isLast: Bool { current != nil && !hasNext }

    /// True once every set has been passed (including immediately, for a
    /// session with zero sets). Drives the session-`ended` lifecycle event.
    public var isFinished: Bool { setIndex >= orderedSets.count }

    /// Moves to the next set. From the last set (or an already-empty/
    /// finished cursor), clamps at `setCount` rather than overshooting —
    /// repeated calls are safe no-ops once `isFinished` is true.
    public mutating func advance() {
        guard setIndex < orderedSets.count else { return }
        setIndex += 1
    }
}
