//
//  SpotEventGate.swift
//  SpottersaurusKit
//
//  `SpotEngine.process(motion:hr:)` re-analyses the *entire* rolling sample
//  buffer on every motion batch, so `SpotAnalysis.events` always contains
//  every event for every rep still inside the buffer window — not just what's
//  new since the last tick. Feeding that whole array straight to
//  `SetLifecycleController.handle(spotEvent:)` on every tick means a single
//  `.rackIt` gets re-raised continuously, and even re-latches the alert right
//  back after a lifter resolves it, because the very next batch replays the
//  same already-seen event (see docs/backlog.md P1-1c).
//
//  `SpotEventGate` is the fix: a tiny pure identity filter the caller folds
//  events through before handing them to the lifecycle. An event's identity
//  is its `(kind, repIndex)` pair — the same rep reaching the same escalation
//  stage twice (e.g. because it's still inside the rolling buffer on the next
//  tick) is the *same* event and is only ever admitted once; a different rep,
//  or a different stage for the same rep (grinding → resolved → a fresh
//  grinding on a later rep), is genuinely new and always gets through.
//
//  Pure value type, no wall-clock, no I/O — mirrors `SetLifecycleController`'s
//  discipline so it's trivially unit-testable headless.
//

import Foundation

/// Filters a stream of `SpotEvent`s down to ones not yet seen, remembering
/// what it has admitted so replayed buffers never re-yield the same event.
public struct SpotEventGate: Sendable, Equatable {

    /// An event's identity for dedup purposes: which rep, at which stage.
    /// Deliberately excludes `timestamp`/`confidence`/`reason` — those can
    /// drift slightly as the rolling buffer's segmentation is recomputed on
    /// later ticks, but it's still the same real-world escalation.
    private struct Key: Hashable {
        var kind: SpotEventKind
        var repIndex: Int
    }

    private var seen: Set<Key> = []

    public init() {}

    /// Returns the subset of `events` not previously admitted by this gate,
    /// in order, and marks them as seen so a later call with the same (or an
    /// overlapping) buffer never re-yields them.
    public mutating func admitNew(from events: [SpotEvent]) -> [SpotEvent] {
        var admitted: [SpotEvent] = []
        for event in events {
            let key = Key(kind: event.kind, repIndex: event.repIndex)
            if seen.insert(key).inserted {
                admitted.append(event)
            }
        }
        return admitted
    }

    /// Resets the gate — call when a new set is armed so the next set starts
    /// with a clean slate (rep 0's events shouldn't be permanently silenced by
    /// the previous set's rep 0).
    public mutating func reset() {
        seen.removeAll()
    }
}
