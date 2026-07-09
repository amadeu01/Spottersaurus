//
//  BodyWeightEntry.swift
//  SpottersaurusKit
//
//  Minimal body-weight store (H3). Apple Health only ever gives us the single
//  most-recent bodyMass sample (`ImportedBodyWeight`), and the Profile screen
//  (P1) only needs "the current body weight", so this deliberately holds at
//  most one row rather than a full history — `HealthSyncPersister` upserts the
//  same record in place on every sync. Standalone, no owning relationship.
//

import Foundation
import SwiftData

/// The lifter's most recently known body weight, imported from Apple Health.
@Model
public final class BodyWeightEntry {
    public var id: UUID = UUID()
    /// When this weight was recorded (the HealthKit sample date, not the sync
    /// time).
    public var date: Date = Date()
    public var kilograms: Double = 0

    public init(date: Date, kilograms: Double, id: UUID = UUID()) {
        self.id = id
        self.date = date
        self.kilograms = kilograms
    }
}
