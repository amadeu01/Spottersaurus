//
//  Progression+FiveThreeOne.swift
//  SpottersaurusKit
//
//  Wendler 5/3/1: training max = 90% of 1RM. Three main weeks wave through
//  65/75/85%, 70/80/90%, 75/85/95% of the training max at 5/3/1 top-set reps
//  (last set of each week is AMRAP). After a completed cycle the training max
//  bumps by a lift-specific fixed amount, rounded to the barbell increment.
//

import Foundation

extension Progression {

    /// Fraction of a true/estimated 1RM that becomes the 5/3/1 training max.
    public static let fiveThreeOneTrainingMaxFraction: Double = 0.9

    /// Compute a 5/3/1 training max from a 1RM: `oneRepMaxKg * 0.9`, rounded
    /// to `increment`.
    public static func fiveThreeOneTrainingMaxKg(
        oneRepMaxKg: Double,
        increment: Double = defaultIncrementKg
    ) -> Double {
        round(oneRepMaxKg * fiveThreeOneTrainingMaxFraction, to: increment)
    }

    /// One prescribed step in a 5/3/1 main-work scheme: a percent of the
    /// training max, a target rep count, and whether it's the week's AMRAP
    /// top set.
    public struct FiveThreeOneStep: Sendable, Equatable {
        public let percent: Double
        public let reps: Int
        public let isAMRAP: Bool

        public init(percent: Double, reps: Int, isAMRAP: Bool) {
            self.percent = percent
            self.reps = reps
            self.isAMRAP = isAMRAP
        }
    }

    /// The three-set main-work scheme for a given 5/3/1 wave week (1...3).
    /// Week 1: 65/75/85% x 5/5/5+. Week 2: 70/80/90% x 3/3/3+.
    /// Week 3: 75/85/95% x 5/3/1+. The last set of every week is AMRAP.
    /// Unknown week numbers return an empty scheme.
    public static func fiveThreeOneScheme(week: Int) -> [FiveThreeOneStep] {
        switch week {
        case 1:
            return [
                FiveThreeOneStep(percent: 65, reps: 5, isAMRAP: false),
                FiveThreeOneStep(percent: 75, reps: 5, isAMRAP: false),
                FiveThreeOneStep(percent: 85, reps: 5, isAMRAP: true),
            ]
        case 2:
            return [
                FiveThreeOneStep(percent: 70, reps: 3, isAMRAP: false),
                FiveThreeOneStep(percent: 80, reps: 3, isAMRAP: false),
                FiveThreeOneStep(percent: 90, reps: 3, isAMRAP: true),
            ]
        case 3:
            return [
                FiveThreeOneStep(percent: 75, reps: 5, isAMRAP: false),
                FiveThreeOneStep(percent: 85, reps: 3, isAMRAP: false),
                FiveThreeOneStep(percent: 95, reps: 1, isAMRAP: true),
            ]
        default:
            return []
        }
    }

    /// Resolve a 5/3/1 main-work weight: `percent` of `trainingMaxKg`,
    /// rounded to `increment`. `percent` is a whole-percent value (e.g. `85`
    /// means 85% of the training max), matching `FiveThreeOneStep.percent`.
    public static func fiveThreeOneWeightKg(
        trainingMaxKg: Double,
        percent: Double,
        increment: Double = defaultIncrementKg
    ) -> Double {
        round(trainingMaxKg * percent / 100.0, to: increment)
    }

    /// The fixed 5/3/1 training-max bump applied after a completed cycle,
    /// upper-body (bench) vs lower-body (squat, deadlift). Accessory work has
    /// no training max to bump, so it defaults to the (smaller) upper bump.
    public static let fiveThreeOneUpperBumpKg: Double = 2.5
    public static let fiveThreeOneLowerBumpKg: Double = 5.0

    /// Bump a training max after a completed 5/3/1 cycle: `+2.5kg` for bench,
    /// `+5kg` for squat/deadlift, rounded to `increment`.
    public static func bumpedTrainingMaxKg(
        currentTrainingMaxKg: Double,
        lift: LiftKind,
        increment: Double = defaultIncrementKg
    ) -> Double {
        let bump: Double = switch lift {
        case .squat, .deadlift: fiveThreeOneLowerBumpKg
        case .bench, .accessory: fiveThreeOneUpperBumpKg
        }
        return round(currentTrainingMaxKg + bump, to: increment)
    }
}
