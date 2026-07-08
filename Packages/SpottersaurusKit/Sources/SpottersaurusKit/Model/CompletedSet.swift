//
//  CompletedSet.swift
//  SpottersaurusKit
//
//  A set the lifter actually performed: the load, reps, per-rep metrics, any
//  spotter (grind / RACK IT) events, and the velocity summary. Owned by a
//  `WorkoutSession` (cascade delete) and owns its `RepMetric`s (cascade). e1RM
//  is derived from weight × reps via Epley — never stored, so it can't drift.
//

import Foundation
import SwiftData

/// The Epley one-rep-max estimator. Single-sourced so every call site (model,
/// charts, progression) agrees: `e1RM = w × (1 + reps / 30)`.
public enum Epley {
    /// Estimated 1RM (kg) for a weight lifted for `reps`. Returns the raw weight
    /// for a single rep and 0 for a non-positive rep count.
    public static func e1RM(weightKg: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        return weightKg * (1.0 + Double(reps) / 30.0)
    }
}

/// A spotter escalation that fired during a set. Stored inline on the set as a
/// `Codable` value so it mirrors through CloudKit without a separate table.
public struct SpotterEvent: Codable, Sendable, Equatable, Hashable {
    /// The two-stage escalation level.
    public enum Stage: String, Codable, Sendable {
        /// Soft "grinding" nudge.
        case grind
        /// Loud "RACK IT" alert.
        case rackIt
    }

    public var stage: Stage
    /// Seconds since the set was armed (monotonic), matching the sample clock.
    public var timestamp: TimeInterval
    /// Which rep index the event fired on, if known.
    public var repIndex: Int?
    /// Lifter dismissed it as a false alarm — feeds threshold tuning later.
    public var wasFalseAlarm: Bool

    public init(stage: Stage, timestamp: TimeInterval, repIndex: Int? = nil, wasFalseAlarm: Bool = false) {
        self.stage = stage
        self.timestamp = timestamp
        self.repIndex = repIndex
        self.wasFalseAlarm = wasFalseAlarm
    }
}

/// A performed set with its metrics and spotter events.
@Model
public final class CompletedSet {
    public var id: UUID = UUID()
    /// Wall-clock start of the set.
    public var startedAt: Date = Date()
    /// Bar weight used, in kilograms.
    public var weightKg: Double = 0
    /// Reps actually completed.
    public var repsPerformed: Int = 0
    /// Average concentric velocity across the set, m/s (VBT).
    public var avgConcentricVelocityMS: Double = 0
    /// Peak concentric velocity across the set, m/s (VBT).
    public var peakConcentricVelocityMS: Double = 0
    /// Spotter escalations that fired, stored inline as a Codable attribute.
    public var spotterEvents: [SpotterEvent] = []

    /// The owning session (inverse of `WorkoutSession.completedSets`).
    public var session: WorkoutSession?
    /// The exercise performed. Nullify-on-delete reference; inverse declared on
    /// `Exercise.completedSets`.
    public var exercise: Exercise?

    /// Per-rep metrics. Cascade delete: removing the set removes its metrics.
    @Relationship(deleteRule: .cascade, inverse: \RepMetric.completedSet)
    public var repMetrics: [RepMetric]?

    public init(
        exercise: Exercise?,
        weightKg: Double,
        repsPerformed: Int,
        startedAt: Date = Date(),
        avgConcentricVelocityMS: Double = 0,
        peakConcentricVelocityMS: Double = 0,
        spotterEvents: [SpotterEvent] = [],
        id: UUID = UUID()
    ) {
        self.id = id
        self.exercise = exercise
        self.weightKg = weightKg
        self.repsPerformed = repsPerformed
        self.startedAt = startedAt
        self.avgConcentricVelocityMS = avgConcentricVelocityMS
        self.peakConcentricVelocityMS = peakConcentricVelocityMS
        self.spotterEvents = spotterEvents
    }

    /// Estimated 1RM (kg) for this set via Epley. Derived, never stored.
    public var estimatedOneRepMaxKg: Double {
        Epley.e1RM(weightKg: weightKg, reps: repsPerformed)
    }

    /// Per-rep metrics sorted by rep index.
    public var orderedRepMetrics: [RepMetric] {
        (repMetrics ?? []).sorted { $0.repIndex < $1.repIndex }
    }

    public func appendRepMetric(_ metric: RepMetric) {
        var existing = repMetrics ?? []
        existing.append(metric)
        repMetrics = existing
    }
}
