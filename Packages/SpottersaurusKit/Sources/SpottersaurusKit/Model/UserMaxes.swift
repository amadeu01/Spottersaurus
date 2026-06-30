//
//  UserMaxes.swift
//  SpottersaurusKit
//
//  Per-lift strength anchors used for percentage-based programming. One record
//  per `LiftKind`: the working training max (what 5/3/1 percentages scale) and
//  the true / estimated 1RM. Standalone — no owning relationship.
//

import Foundation
import SwiftData

/// A lifter's training max and 1RM for a single lift.
@Model
public final class UserMaxes {
    public var id: UUID = UUID()
    /// The lift these maxes apply to.
    public var lift: LiftKind = LiftKind.squat
    /// Training max (kg) — the value program percentages scale (typically ~90%
    /// of the true 1RM in 5/3/1).
    public var trainingMaxKg: Double = 0
    /// True or estimated one-rep max (kg).
    public var oneRepMaxKg: Double = 0
    public var updatedAt: Date = Date()

    public init(
        lift: LiftKind,
        trainingMaxKg: Double,
        oneRepMaxKg: Double,
        updatedAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.lift = lift
        self.trainingMaxKg = trainingMaxKg
        self.oneRepMaxKg = oneRepMaxKg
        self.updatedAt = updatedAt
    }
}
