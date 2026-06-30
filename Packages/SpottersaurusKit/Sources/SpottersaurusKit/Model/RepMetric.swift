//
//  RepMetric.swift
//  SpottersaurusKit
//
//  Per-rep metrics captured by the detection engine for one concentric. Owned
//  by a `CompletedSet` (cascade delete). `repIndex` holds explicit order within
//  the set since relationship arrays are unordered under SwiftData / CloudKit.
//

import Foundation
import SwiftData

/// Detection output for a single rep: how long the concentric took, the
/// velocity profile, a range-of-motion proxy, and whether the engine flagged a
/// stall on this rep.
@Model
public final class RepMetric {
    public var id: UUID = UUID()
    /// Zero-based position of this rep within its set.
    public var repIndex: Int = 0
    /// Concentric (lifting phase) duration, in seconds.
    public var concentricSeconds: Double = 0
    /// Peak concentric velocity, in metres per second (VBT).
    public var peakVelocityMS: Double = 0
    /// Mean concentric velocity, in metres per second (VBT).
    public var meanVelocityMS: Double = 0
    /// Range-of-motion proxy (integrated displacement, normalised). Unitless.
    public var romProxy: Double = 0
    /// Whether the engine flagged this rep as a stall / grind.
    public var flaggedStall: Bool = false

    /// The owning set (inverse of `CompletedSet.repMetrics`).
    public var completedSet: CompletedSet?

    public init(
        repIndex: Int,
        concentricSeconds: Double,
        peakVelocityMS: Double,
        meanVelocityMS: Double,
        romProxy: Double = 0,
        flaggedStall: Bool = false,
        id: UUID = UUID()
    ) {
        self.id = id
        self.repIndex = repIndex
        self.concentricSeconds = concentricSeconds
        self.peakVelocityMS = peakVelocityMS
        self.meanVelocityMS = meanVelocityMS
        self.romProxy = romProxy
        self.flaggedStall = flaggedStall
    }
}
