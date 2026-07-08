//
//  Progression+Linear.swift
//  SpottersaurusKit
//
//  Linear progression: add a fixed per-session increment to the working
//  weight — upper-body (bench) vs lower-body (squat, deadlift) — rounded to
//  the barbell increment. No training-max concept; the working weight itself
//  is the state that advances.
//

import Foundation

extension Progression {

    /// Default per-session linear-progression increments.
    public static let linearUpperIncrementKg: Double = 2.5
    public static let linearLowerIncrementKg: Double = 5.0

    /// The next linear-progression working weight: `currentWeightKg` plus
    /// `upperIncrementKg` for bench, `lowerIncrementKg` for squat/deadlift
    /// (accessory work defaults to the smaller upper increment), rounded to
    /// `increment`.
    public static func nextLinearWeightKg(
        currentWeightKg: Double,
        lift: LiftKind,
        upperIncrementKg: Double = linearUpperIncrementKg,
        lowerIncrementKg: Double = linearLowerIncrementKg,
        increment: Double = defaultIncrementKg
    ) -> Double {
        let bump: Double = switch lift {
        case .squat, .deadlift: lowerIncrementKg
        case .bench, .accessory: upperIncrementKg
        }
        return round(currentWeightKg + bump, to: increment)
    }
}
