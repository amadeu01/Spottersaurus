//
//  Exercise.swift
//  SpottersaurusKit
//
//  The library entry for a lift. Carries the `LiftKind` taxonomy and derives
//  its bar-tracking profile (which selects the detection path) straight from
//  `LiftKind.barTracking` — never duplicated here. Referenced by both planned
//  and completed sets, so an `Exercise` is shared, never cascade-deleted when a
//  set that points at it is removed.
//

import Foundation
import SwiftData

/// A named lift in the user's library. CloudKit-friendly: every stored
/// attribute has a default, and the inverse relationships use `.nullify` so
/// deleting a set never deletes the shared exercise.
@Model
public final class Exercise {
    /// Stable identity that survives CloudKit mirroring.
    public var id: UUID = UUID()
    /// Human-facing name, e.g. "Back Squat".
    public var name: String = ""
    /// The lift taxonomy; persisted by raw value via `LiftKind: Codable`.
    public var kind: LiftKind = LiftKind.accessory
    public var createdAt: Date = Date()

    /// Planned sets that reference this exercise. Nullify on delete — removing
    /// a planned set must not remove the shared exercise.
    @Relationship(deleteRule: .nullify, inverse: \PlannedSet.exercise)
    public var plannedSets: [PlannedSet]?

    /// Completed sets that reference this exercise. Nullify on delete.
    @Relationship(deleteRule: .nullify, inverse: \CompletedSet.exercise)
    public var completedSets: [CompletedSet]?

    public init(name: String, kind: LiftKind, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
    }

    /// Bar-tracking profile, derived (never stored) from the lift kind so the
    /// detection path stays single-sourced in `LiftKind`.
    public var barTracking: BarTracking { kind.barTracking }

    /// Whether wrist-velocity (VBT) drives the alert trigger for this exercise
    /// (see `LiftKind.velocityDrivesAlerts`).
    public var velocityDrivesAlerts: Bool { kind.velocityDrivesAlerts }

    /// Whether `SpotEngine` computes and reports a velocity number for this
    /// exercise (see `LiftKind.computesVelocity`).
    public var computesVelocity: Bool { kind.computesVelocity }

    /// Deprecated alias of `velocityDrivesAlerts` (ADR 0009).
    @available(*, deprecated, renamed: "velocityDrivesAlerts")
    public var usesVelocityPath: Bool { kind.velocityDrivesAlerts }
}
