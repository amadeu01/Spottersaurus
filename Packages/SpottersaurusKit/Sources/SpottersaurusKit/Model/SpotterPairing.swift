//
//  SpotterPairing.swift
//  SpottersaurusKit
//
//  A linked human spotter who can receive Stage-2 ("RACK IT") push alerts. The
//  spotter is identified by an opaque string (CloudKit share participant / user
//  record id), and the lifter chooses which lifts actually push them. Standalone.
//

import Foundation
import SwiftData

/// A paired spotter and the lifts they're alerted on.
@Model
public final class SpotterPairing {
    public var id: UUID = UUID()
    /// Opaque spotter identifier (CloudKit share participant / account id).
    public var spotterIdentifier: String = ""
    /// Display name shown in the pairing UI, if available.
    public var displayName: String = ""
    /// Lifts that push this spotter on a Stage-2 alert. Stored inline as a
    /// Codable attribute.
    public var enabledLifts: [LiftKind] = []
    /// Master on/off for the pairing without losing the per-lift selection.
    public var isEnabled: Bool = true
    public var createdAt: Date = Date()

    public init(
        spotterIdentifier: String,
        displayName: String = "",
        enabledLifts: [LiftKind] = [],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.spotterIdentifier = spotterIdentifier
        self.displayName = displayName
        self.enabledLifts = enabledLifts
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// Whether this pairing should push for the given lift right now.
    public func alerts(for lift: LiftKind) -> Bool {
        isEnabled && enabledLifts.contains(lift)
    }
}
