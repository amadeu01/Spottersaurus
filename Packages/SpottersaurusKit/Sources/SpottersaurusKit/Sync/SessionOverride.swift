//
//  SessionOverride.swift
//  SpottersaurusKit
//
//  Phase 0.2 M2 — the ephemeral, per-send adjustment a lifter can make on the
//  iPhone before "Send to Watch" (bump/drop weight, change reps/rest/AMRAP/
//  lift for a set). See the "Session Override" glossary entry in
//  `CONTEXT.md`: it is a per-set edit keyed by `PlannedSetEnvelope.id`,
//  applied to an already-resolved `PlannedSessionEnvelope` (the output of
//  `PlannedSessionEnvelope.make(program:day:maxes:)`). It NEVER mutates the
//  saved `Program`/`PlannedSet` SwiftData models — those are only read once,
//  up front, to produce the base envelope; everything downstream of that is
//  a pure value-type rewrite of the envelope copy.
//

import Foundation

/// A single set's overridable fields. Every field is optional: `nil` means
/// "keep the base envelope's value for this field". `SetOverride.empty`
/// (all-nil) is the identity element — applying it changes nothing.
public struct SetOverride: Sendable, Equatable {
    public var lift: LiftKind?
    public var targetReps: Int?
    public var weightKg: Double?
    public var restSeconds: Int?
    public var isAMRAP: Bool?

    public init(
        lift: LiftKind? = nil,
        targetReps: Int? = nil,
        weightKg: Double? = nil,
        restSeconds: Int? = nil,
        isAMRAP: Bool? = nil
    ) {
        self.lift = lift
        self.targetReps = targetReps
        self.weightKg = weightKg
        self.restSeconds = restSeconds
        self.isAMRAP = isAMRAP
    }

    /// All fields nil — applying this changes nothing about the set.
    public static let empty = SetOverride()

    public var isEmpty: Bool { self == .empty }
}

/// An ephemeral, per-send adjustment to a `PlannedSessionEnvelope`: per-set
/// edits keyed by `PlannedSetEnvelope.id`. Built and consumed entirely on the
/// iPhone at send time — never persisted, never written back to the
/// `Program`/`PlannedSet` SwiftData models.
public struct SessionOverride: Sendable, Equatable {
    /// Per-set edits, keyed by `PlannedSetEnvelope.id`. A set with no entry
    /// here (or an entry equal to `.empty`) is unmodified.
    public var setOverrides: [UUID: SetOverride]

    public init(setOverrides: [UUID: SetOverride] = [:]) {
        self.setOverrides = setOverrides
    }

    /// No overrides at all — the default, empty state an editor session
    /// starts in.
    public static let empty = SessionOverride()

    /// `true` if applying this override would change nothing (either no
    /// entries, or every entry is itself empty).
    public var isEmpty: Bool {
        setOverrides.values.allSatisfy(\.isEmpty)
    }

    /// Returns a new `PlannedSessionEnvelope` with each set's overridden
    /// fields applied. Session-level metadata (`id`/`programName`/`dayName`/
    /// `createdAt`), set order, and set count are always preserved; sets
    /// without a (non-empty) override entry pass through unchanged. An
    /// override keyed by an id absent from `base.sets` is inert (defensive —
    /// e.g. a stale editor state after the underlying program day changed).
    ///
    /// Pure: reads only `base` and `self`, touches no SwiftData model.
    public func apply(to base: PlannedSessionEnvelope) -> PlannedSessionEnvelope {
        guard !isEmpty else { return base }

        var adjusted = base
        adjusted.sets = base.sets.map { set in
            guard let override = setOverrides[set.id], !override.isEmpty else { return set }
            var set = set
            if let lift = override.lift { set.lift = lift }
            if let targetReps = override.targetReps { set.targetReps = targetReps }
            if let weightKg = override.weightKg { set.weightKg = weightKg }
            if let restSeconds = override.restSeconds { set.restSeconds = restSeconds }
            if let isAMRAP = override.isAMRAP { set.isAMRAP = isAMRAP }
            return set
        }
        return adjusted
    }
}
