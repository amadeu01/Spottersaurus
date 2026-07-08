//
//  SetRecord.swift
//  SpottersaurusKit
//
//  A lightweight, hardware-free snapshot of a logged set — the plain input the
//  Analytics layer computes over. Callers derive it from `CompletedSet` (+ its
//  owning `WorkoutSession`/`Exercise`) or construct it directly in tests; the
//  Analytics functions never depend on SwiftData.
//

import Foundation

/// A single logged set, reduced to the fields the analytics layer needs:
/// which lift, when, at what load/reps, an optional VBT velocity reading, and
/// any spotter escalations that fired during it.
public struct SetRecord: Sendable, Equatable {
    public var lift: LiftKind
    public var date: Date
    /// Bar weight used, in kilograms.
    public var weightKg: Double
    /// Reps completed.
    public var reps: Int
    /// Mean concentric velocity for the set, m/s (VBT). `nil` when the lift's
    /// detection path doesn't produce a velocity reading (e.g. back-loaded
    /// squat) or the set predates velocity capture.
    public var meanConcentricVelocityMS: Double?
    /// Spotter escalations that fired during this set.
    public var spotterEvents: [SpotterEvent]

    public init(
        lift: LiftKind,
        date: Date,
        weightKg: Double,
        reps: Int,
        meanConcentricVelocityMS: Double? = nil,
        spotterEvents: [SpotterEvent] = []
    ) {
        self.lift = lift
        self.date = date
        self.weightKg = weightKg
        self.reps = reps
        self.meanConcentricVelocityMS = meanConcentricVelocityMS
        self.spotterEvents = spotterEvents
    }
}
