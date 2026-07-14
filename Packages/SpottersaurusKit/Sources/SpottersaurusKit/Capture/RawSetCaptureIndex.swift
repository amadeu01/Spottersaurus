//
//  RawSetCaptureIndex.swift
//  SpottersaurusKit
//
//  Pure, Foundation-only grouping + retention logic for stored raw-set
//  captures (ADR 0008 / PRC-3). The iPhone receiver (`WatchLink` /
//  `RawSetCaptureStore`) copies each transferred capture file to disk and
//  records its identity here; this type answers "what captures exist,
//  grouped workout → exercise → set" and "which captures should be deleted
//  under a keep-last-N-workouts retention policy". No WatchConnectivity, no
//  SwiftData, no file I/O — so it is fully unit-tested on macOS via
//  `swift test`, and the device side stays a thin adapter over it.
//

import Foundation

/// The minimal identity of one stored capture file, carried in the
/// Watch → iPhone `transferFile` metadata (see
/// `WatchPlannedSessionStore.transfer(rawSetCapture:)`) and reconstructable
/// from the capture header. `fileName` is the local on-disk reference (a
/// capture is stored one file per set, named by `setID`); everything else is
/// grouping/recency metadata. Pure value type so the index is trivially
/// testable and `Codable` for the on-disk sidecar the device side persists.
public struct RawSetCaptureIdentity: Codable, Sendable, Equatable, Hashable {
    /// The workout (planned session) this set belongs to — the top grouping
    /// level.
    public var sessionID: UUID
    /// The specific set — the leaf grouping level and the file's stable id.
    public var setID: UUID
    /// This set's position within its exercise (0-based), for ordering sets.
    public var setIndex: Int
    /// Total planned sets for this exercise, for display context.
    public var setCount: Int
    /// The exercise (middle grouping level).
    public var lift: LiftKind
    /// Wall-clock arm time — the recency key used for retention ordering.
    public var armedAt: Date
    /// Local on-disk file reference (relative name within the captures
    /// directory). Also the dedupe key: re-transferring the same set replaces
    /// its identity in the index rather than duplicating it.
    public var fileName: String

    public init(
        sessionID: UUID,
        setID: UUID,
        setIndex: Int,
        setCount: Int,
        lift: LiftKind,
        armedAt: Date,
        fileName: String
    ) {
        self.sessionID = sessionID
        self.setID = setID
        self.setIndex = setIndex
        self.setCount = setCount
        self.lift = lift
        self.armedAt = armedAt
        self.fileName = fileName
    }
}

/// The leaf grouping level: all captures recorded for one set (usually one,
/// more if a set was re-armed and re-transferred), newest first.
public struct CaptureSetGroup: Sendable, Equatable {
    public let setID: UUID
    public let setIndex: Int
    public let setCount: Int
    /// Captures for this set, newest `armedAt` first.
    public let captures: [RawSetCaptureIdentity]
    /// Recency key: the newest capture's `armedAt`.
    public let armedAt: Date
}

/// The middle grouping level: one exercise (lift) within a workout, with its
/// sets ordered by `setIndex`.
public struct CaptureExerciseGroup: Sendable, Equatable {
    public let lift: LiftKind
    /// Sets ordered by `setIndex` ascending.
    public let sets: [CaptureSetGroup]
    /// Recency key: the newest capture's `armedAt` across this exercise.
    public let armedAt: Date
}

/// The top grouping level: one workout (planned session), with its exercises
/// ordered chronologically by when they were first captured.
public struct CaptureWorkoutGroup: Sendable, Equatable {
    public let sessionID: UUID
    /// Exercises ordered by their earliest capture (chronological within the
    /// workout).
    public let exercises: [CaptureExerciseGroup]
    /// Recency key: the newest capture's `armedAt` across the whole workout —
    /// this is what retention ranks workouts by.
    public let armedAt: Date
}

/// Pure index over stored capture identities: grouping (workout → exercise →
/// set) and keep-last-N-workouts retention. Holds no bytes and touches no
/// disk — the device side maps `identitiesToPrune`/`prune` results onto
/// actual file deletions.
public struct RawSetCaptureIndex: Sendable, Equatable, Codable {
    /// The recorded identities, in insertion order. Grouping/ordering is
    /// derived on demand (`workouts`) so insertion stays O(1)-ish and the
    /// stored form is stable for the on-disk sidecar.
    public private(set) var identities: [RawSetCaptureIdentity]

    public init(_ identities: [RawSetCaptureIdentity] = []) {
        self.identities = identities
    }

    // MARK: Mutation

    /// Records a capture identity, replacing any existing one with the same
    /// `fileName` (a re-transfer of the same set overwrites its file, so it
    /// must overwrite its identity too rather than duplicate it).
    public mutating func insert(_ identity: RawSetCaptureIdentity) {
        if let existing = identities.firstIndex(where: { $0.fileName == identity.fileName }) {
            identities[existing] = identity
        } else {
            identities.append(identity)
        }
    }

    /// Manual delete of a single capture file by name. Returns the removed
    /// identity, or `nil` if none matched.
    @discardableResult
    public mutating func remove(fileName: String) -> RawSetCaptureIdentity? {
        guard let idx = identities.firstIndex(where: { $0.fileName == fileName }) else {
            return nil
        }
        return identities.remove(at: idx)
    }

    /// Manual delete of every capture recorded for a set. Returns the removed
    /// identities (so the caller can delete the corresponding files).
    @discardableResult
    public mutating func removeSet(_ setID: UUID) -> [RawSetCaptureIdentity] {
        let removed = identities.filter { $0.setID == setID }
        identities.removeAll { $0.setID == setID }
        return removed
    }

    // MARK: Listing

    /// All captures recorded for a set, newest `armedAt` first — the per-set
    /// listing API PRC-3 requires.
    public func captures(forSet setID: UUID) -> [RawSetCaptureIdentity] {
        identities
            .filter { $0.setID == setID }
            .sorted(by: Self.captureOrder)
    }

    /// The full workout → exercise → set hierarchy, workouts newest first.
    public var workouts: [CaptureWorkoutGroup] {
        let bySession = Dictionary(grouping: identities, by: \.sessionID)

        let groups: [CaptureWorkoutGroup] = bySession.map { sessionID, sessionIdentities in
            let byLift = Dictionary(grouping: sessionIdentities, by: \.lift)

            let exercises: [CaptureExerciseGroup] = byLift.map { lift, liftIdentities in
                let bySet = Dictionary(grouping: liftIdentities, by: \.setID)

                let sets: [CaptureSetGroup] = bySet.map { setID, setIdentities in
                    let ordered = setIdentities.sorted(by: Self.captureOrder)
                    let first = ordered[0]
                    return CaptureSetGroup(
                        setID: setID,
                        setIndex: first.setIndex,
                        setCount: first.setCount,
                        captures: ordered,
                        armedAt: ordered.map(\.armedAt).max() ?? first.armedAt
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.setIndex != rhs.setIndex { return lhs.setIndex < rhs.setIndex }
                    if lhs.armedAt != rhs.armedAt { return lhs.armedAt < rhs.armedAt }
                    return lhs.setID.uuidString < rhs.setID.uuidString
                }

                return CaptureExerciseGroup(
                    lift: lift,
                    sets: sets,
                    armedAt: liftIdentities.map(\.armedAt).max() ?? Date.distantPast
                )
            }
            // Exercises in the order they were first performed (chronological).
            .sorted { lhs, rhs in
                let lFirst = lhs.sets.flatMap(\.captures).map(\.armedAt).min() ?? Date.distantPast
                let rFirst = rhs.sets.flatMap(\.captures).map(\.armedAt).min() ?? Date.distantPast
                if lFirst != rFirst { return lFirst < rFirst }
                return lhs.lift.rawValue < rhs.lift.rawValue
            }

            return CaptureWorkoutGroup(
                sessionID: sessionID,
                exercises: exercises,
                armedAt: sessionIdentities.map(\.armedAt).max() ?? Date.distantPast
            )
        }

        return groups.sorted(by: Self.workoutRecencyOrder)
    }

    // MARK: Retention

    /// The identities that a keep-last-`n`-workouts retention policy would
    /// delete: everything belonging to workouts older than the `n` most
    /// recent (by newest `armedAt`). `n <= 0` prunes everything; `n` ≥ the
    /// number of workouts prunes nothing. Deterministic: workouts are ranked
    /// by recency, ties broken by `sessionID`.
    public func identitiesToPrune(keepingLastSessions n: Int) -> [RawSetCaptureIdentity] {
        guard n > 0 else { return identities }

        let ranked = workouts // already newest-first
        guard ranked.count > n else { return [] }

        let doomedSessionIDs = Set(ranked.dropFirst(n).map(\.sessionID))
        return identities.filter { doomedSessionIDs.contains($0.sessionID) }
    }

    /// Applies keep-last-`n`-workouts retention, dropping the pruned
    /// identities from the index and returning them so the caller can delete
    /// the corresponding files.
    @discardableResult
    public mutating func prune(keepingLastSessions n: Int) -> [RawSetCaptureIdentity] {
        let doomed = identitiesToPrune(keepingLastSessions: n)
        guard !doomed.isEmpty else { return [] }
        let doomedFiles = Set(doomed.map(\.fileName))
        identities.removeAll { doomedFiles.contains($0.fileName) }
        return doomed
    }

    // MARK: Ordering helpers

    /// Newest capture first; ties broken deterministically by `fileName`.
    private static func captureOrder(_ lhs: RawSetCaptureIdentity, _ rhs: RawSetCaptureIdentity) -> Bool {
        if lhs.armedAt != rhs.armedAt { return lhs.armedAt > rhs.armedAt }
        return lhs.fileName < rhs.fileName
    }

    /// Newest workout first; ties broken deterministically by `sessionID`.
    private static func workoutRecencyOrder(_ lhs: CaptureWorkoutGroup, _ rhs: CaptureWorkoutGroup) -> Bool {
        if lhs.armedAt != rhs.armedAt { return lhs.armedAt > rhs.armedAt }
        return lhs.sessionID.uuidString < rhs.sessionID.uuidString
    }
}
