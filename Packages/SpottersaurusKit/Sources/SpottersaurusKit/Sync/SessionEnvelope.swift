//
//  SessionEnvelope.swift
//  SpottersaurusKit
//
//  Codable DTOs for the Watch <-> iPhone link. Live in-set data and the
//  finished-session handoff travel as these envelopes over WatchConnectivity
//  (NOT CloudKit — too slow for live). Pure value types; the `WatchLink`
//  WCSession wrapper lands in Phase 6.
//

import Foundation

/// A finished-set summary handed from the Watch executor to the iPhone
/// reviewer. Deliberately minimal scaffolding — per-rep metrics and spotter
/// events are layered on in later phases.
public struct CompletedSetEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var lift: LiftKind
    /// Wall-clock start of the set (ISO-8601 when JSON-encoded).
    public var startedAt: Date
    public var weightKg: Double
    public var repsCompleted: Int

    public init(
        id: UUID = UUID(),
        lift: LiftKind,
        startedAt: Date,
        weightKg: Double,
        repsCompleted: Int
    ) {
        self.id = id
        self.lift = lift
        self.startedAt = startedAt
        self.weightKg = weightKg
        self.repsCompleted = repsCompleted
    }
}

/// The top-level envelope for a finished session handed off to the phone.
public struct SessionEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Wall-clock session date (ISO-8601 when JSON-encoded).
    public var date: Date
    public var sets: [CompletedSetEnvelope]

    public init(id: UUID = UUID(), date: Date, sets: [CompletedSetEnvelope] = []) {
        self.id = id
        self.date = date
        self.sets = sets
    }

    /// Total tonnage (kg) across all sets — a tiny piece of real behavior so
    /// this type carries logic, not just storage.
    public var totalTonnageKg: Double {
        sets.reduce(0) { $0 + $1.weightKg * Double($1.repsCompleted) }
    }
}
