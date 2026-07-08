//
//  ProgramDay.swift
//  SpottersaurusKit
//
//  One training day inside a program, owning an ordered list of planned sets.
//  Order is held explicitly via each set's `sortIndex` (relationship arrays are
//  unordered and CloudKit does not preserve insertion order); `orderedSets`
//  exposes the sorted view callers should read.
//

import Foundation
import SwiftData

/// A day within a `Program`, owning its planned sets with a cascade delete.
@Model
public final class ProgramDay {
    public var id: UUID = UUID()
    /// Day label, e.g. "Day 1 — Squat".
    public var name: String = ""
    /// Position within the owning `Program` (ascending).
    public var sortIndex: Int = 0

    /// The owning program (inverse of `Program.days`).
    public var program: Program?

    /// Planned sets for this day. Cascade delete: removing the day removes its
    /// sets. Read `orderedSets` for the sorted view.
    @Relationship(deleteRule: .cascade, inverse: \PlannedSet.day)
    public var plannedSets: [PlannedSet]?

    public init(name: String, sortIndex: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
    }

    /// Planned sets sorted by their explicit order index.
    public var orderedSets: [PlannedSet] {
        (plannedSets ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    public func appendPlannedSet(_ set: PlannedSet) {
        var existing = plannedSets ?? []
        existing.append(set)
        plannedSets = existing
    }
}
