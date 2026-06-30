//
//  CalibrationProfile.swift
//  SpottersaurusKit
//
//  Per-lift baseline captured from warmup sets, used by `SpotEngine` to decide
//  what "normal" looks like before flagging a grind. Holds the baseline
//  concentric tempo and the expected velocity band for the lift. Standalone.
//

import Foundation
import SwiftData

/// A lifter's calibrated baseline for a single lift.
@Model
public final class CalibrationProfile {
    public var id: UUID = UUID()
    /// The lift this profile calibrates.
    public var lift: LiftKind = LiftKind.bench
    /// Baseline concentric duration (seconds) from clean warmup reps — the
    /// tempo the engine compares working reps against.
    public var baselineConcentricSeconds: Double = 0
    /// Lower bound of the expected concentric velocity band, m/s. Dipping below
    /// this mid-concentric is a stall signal (wrist-tracked lifts only).
    public var velocityBandLowerMS: Double = 0
    /// Upper bound of the expected concentric velocity band, m/s.
    public var velocityBandUpperMS: Double = 0
    public var capturedAt: Date = Date()

    public init(
        lift: LiftKind,
        baselineConcentricSeconds: Double,
        velocityBandLowerMS: Double,
        velocityBandUpperMS: Double,
        capturedAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.lift = lift
        self.baselineConcentricSeconds = baselineConcentricSeconds
        self.velocityBandLowerMS = velocityBandLowerMS
        self.velocityBandUpperMS = velocityBandUpperMS
        self.capturedAt = capturedAt
    }
}
