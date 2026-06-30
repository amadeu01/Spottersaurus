//
//  PlannedSet.swift
//  SpottersaurusKit
//
//  One prescribed set inside a program day. The load is modelled as a
//  `LoadPrescription` — either an absolute bar weight or a percentage of the
//  lift's training max — so percentage-based templates (5/3/1) and fixed-load
//  templates (linear progression) share one type. Order within a day is held by
//  `sortIndex`; SwiftData relationship arrays are unordered, so order is made
//  explicit and CloudKit-safe rather than relying on insertion order.
//

import Foundation
import SwiftData

/// How a planned set's load is expressed. `Codable` so SwiftData stores it as a
/// single composite attribute that mirrors cleanly through CloudKit.
public enum LoadPrescription: Codable, Sendable, Equatable, Hashable {
    /// A fixed bar weight in kilograms.
    case absolute(kg: Double)
    /// A fraction of the lift's training max, expressed as a percent value
    /// (e.g. `85` means 85% of the training max).
    case percentOfTrainingMax(percent: Double)

    /// Resolve to a concrete bar weight given the lift's training max (kg).
    /// Absolute loads ignore the max; percentages scale it.
    public func resolvedKg(trainingMaxKg: Double) -> Double {
        switch self {
        case .absolute(let kg): kg
        case .percentOfTrainingMax(let percent): trainingMaxKg * percent / 100.0
        }
    }
}

/// A single prescribed set: exercise, target reps, load, AMRAP flag, rest.
@Model
public final class PlannedSet {
    public var id: UUID = UUID()
    /// Position within the owning `ProgramDay` (ascending). Explicit so order
    /// survives CloudKit mirroring; relationship arrays are unordered.
    public var sortIndex: Int = 0
    /// Target reps for the set. For an AMRAP set this is the rep floor / target.
    public var targetReps: Int = 0
    /// The prescribed load, absolute or percentage-based.
    public var load: LoadPrescription = LoadPrescription.absolute(kg: 0)
    /// As-many-reps-as-possible: the lifter pushes past `targetReps`.
    public var isAMRAP: Bool = false
    /// Rest after this set, in seconds.
    public var restSeconds: Int = 180

    /// The owning day (inverse of `ProgramDay.plannedSets`).
    public var day: ProgramDay?
    /// The exercise this set prescribes. Nullify-on-delete reference; the
    /// inverse is declared on `Exercise.plannedSets`.
    public var exercise: Exercise?

    public init(
        exercise: Exercise?,
        targetReps: Int,
        load: LoadPrescription,
        isAMRAP: Bool = false,
        restSeconds: Int = 180,
        sortIndex: Int = 0,
        id: UUID = UUID()
    ) {
        self.id = id
        self.exercise = exercise
        self.targetReps = targetReps
        self.load = load
        self.isAMRAP = isAMRAP
        self.restSeconds = restSeconds
        self.sortIndex = sortIndex
    }

    /// Concrete bar weight for this set given a training max (kg).
    public func resolvedWeightKg(trainingMaxKg: Double) -> Double {
        load.resolvedKg(trainingMaxKg: trainingMaxKg)
    }
}
