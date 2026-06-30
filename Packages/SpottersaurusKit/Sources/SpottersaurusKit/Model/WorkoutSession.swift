//
//  WorkoutSession.swift
//  SpottersaurusKit
//
//  A logged training session: when it happened, the program it came from (if
//  any), the sets performed, which device captured it, and the HealthKit
//  workout it was written to. Owns its `CompletedSet`s with a cascade delete;
//  the program reference is a nullify link so deleting a program keeps history.
//

import Foundation
import SwiftData

/// Which device captured a session. The Watch is the in-gym executor; the phone
/// covers manual / free-form logging.
public enum SourceDevice: String, Codable, Sendable, CaseIterable {
    case watch
    case phone
}

/// A performed workout session.
@Model
public final class WorkoutSession {
    public var id: UUID = UUID()
    /// Wall-clock session date.
    public var date: Date = Date()
    /// Capturing device.
    public var source: SourceDevice = SourceDevice.watch
    /// The `HKWorkout` UUID this session was written to, once persisted to
    /// Health. Optional — a session may not be mirrored to HealthKit yet.
    public var healthKitWorkoutUUID: UUID?

    /// The program this session was run from, if any (inverse of
    /// `Program.sessions`). Nullify on program delete.
    public var program: Program?

    /// The sets performed. Cascade delete: removing the session removes its
    /// sets (and, transitively, their rep metrics).
    @Relationship(deleteRule: .cascade, inverse: \CompletedSet.session)
    public var completedSets: [CompletedSet] = []

    public init(
        date: Date = Date(),
        source: SourceDevice,
        program: Program? = nil,
        healthKitWorkoutUUID: UUID? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.program = program
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
    }

    /// Total tonnage (kg) across all sets in the session.
    public var totalTonnageKg: Double {
        completedSets.reduce(0) { $0 + $1.weightKg * Double($1.repsPerformed) }
    }
}
