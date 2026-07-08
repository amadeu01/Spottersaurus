//
//  ProgressionTests.swift
//  SpottersaurusKitTests
//
//  Behavioral tests for the pure program-progression engine, driven with
//  worked numeric examples from the 5/3/1 and linear-progression rules.
//

import Testing
@testable import SpottersaurusKit

struct ProgressionTests {

    // MARK: - Rounding

    // Rounding rule: nearest multiple of `increment`, ties round away from
    // zero (up for positive weights) — matches barbell-plate math where you
    // can't load a half-increment, and matches `Program.roundToPlate`.
    @Test func roundsDownToNearestIncrement() {
        #expect(Progression.round(76.0, to: 2.5) == 75.0)
    }

    // Exact tie (0.5 increment away from both neighbors) rounds up.
    @Test func roundsTieAwayFromZero() {
        #expect(Progression.round(76.25, to: 2.5) == 77.5)
    }

    // A non-positive increment has nothing to round to, so the weight passes
    // through unchanged rather than dividing by zero or negating.
    @Test func roundingWithNonPositiveIncrementIsIdentity() {
        #expect(Progression.round(76.5, to: 0) == 76.5)
    }

    // MARK: - %1RM resolution

    @Test func resolvesPercentOf1RMToAbsoluteWeight() {
        // 80% of a 140kg 1RM = 112kg exactly, but 112 is not itself a
        // multiple of the default 2.5kg increment (112 / 2.5 = 44.8), so it
        // rounds up to the nearest loadable plate total: 112.5kg.
        let weight = Progression.resolvedWeightKg(percent: 80, oneRepMaxKg: 140)
        #expect(weight == 112.5)
    }

    @Test func resolvesPercentOf1RMAlreadyOnIncrementUnchanged() {
        // 50% of a 100kg 1RM = 50kg, already a multiple of 2.5kg.
        let weight = Progression.resolvedWeightKg(percent: 50, oneRepMaxKg: 100)
        #expect(weight == 50.0)
    }

    // MARK: - PlannedSet resolution against UserMaxes

    @Test func resolvesPlannedSetPercentLoadAgainstMatchingUserMaxes() {
        let bench = Exercise(name: "Bench Press", kind: .bench)
        let set = PlannedSet(
            exercise: bench,
            targetReps: 5,
            load: .percentOfTrainingMax(percent: 85),
            isAMRAP: true
        )
        let maxes = [UserMaxes(lift: .bench, trainingMaxKg: 90, oneRepMaxKg: 100)]

        // 85% of a 90kg training max = 76.5kg -> rounds up to 77.5kg.
        let weight = Progression.resolvedWeightKg(for: set, maxes: maxes)
        #expect(weight == 77.5)
    }

    // MARK: - 5/3/1 training max

    @Test func trainingMaxIs90PercentOf1RMRounded() {
        // 100kg 1RM -> 90kg training max (90% of 100 is already on-increment).
        let tm = Progression.fiveThreeOneTrainingMaxKg(oneRepMaxKg: 100)
        #expect(tm == 90.0)
    }

    // MARK: - 5/3/1 week scheme

    @Test func week1SchemeIs65_75_85WithFinalAMRAPAtFiveReps() {
        let scheme = Progression.fiveThreeOneScheme(week: 1)
        #expect(scheme.map(\.percent) == [65, 75, 85])
        #expect(scheme.map(\.reps) == [5, 5, 5])
        #expect(scheme.map(\.isAMRAP) == [false, false, true])
    }

    @Test func week2SchemeIs70_80_90WithFinalAMRAPAtThreeReps() {
        let scheme = Progression.fiveThreeOneScheme(week: 2)
        #expect(scheme.map(\.percent) == [70, 80, 90])
        #expect(scheme.map(\.reps) == [3, 3, 3])
        #expect(scheme.map(\.isAMRAP) == [false, false, true])
    }

    @Test func week3SchemeIs75_85_95WithFinalAMRAPAtOneRep() {
        let scheme = Progression.fiveThreeOneScheme(week: 3)
        #expect(scheme.map(\.percent) == [75, 85, 95])
        #expect(scheme.map(\.reps) == [5, 3, 1])
        #expect(scheme.map(\.isAMRAP) == [false, false, true])
    }

    // MARK: - 5/3/1 worked weight example

    @Test func week1TopSetWeightFrom100kg1RM() {
        // 100kg 1RM -> 90kg TM -> week-1 top single (85%) = 76.5kg -> 77.5kg.
        let tm = Progression.fiveThreeOneTrainingMaxKg(oneRepMaxKg: 100)
        let topStep = Progression.fiveThreeOneScheme(week: 1).last!
        let weight = Progression.fiveThreeOneWeightKg(trainingMaxKg: tm, percent: topStep.percent)
        #expect(weight == 77.5)
    }

    // MARK: - 5/3/1 training-max bump (upper vs lower)

    @Test func benchTrainingMaxBumpsBy2Point5kgAfterACycle() {
        let bumped = Progression.bumpedTrainingMaxKg(currentTrainingMaxKg: 90, lift: .bench)
        #expect(bumped == 92.5)
    }

    @Test func squatTrainingMaxBumpsBy5kgAfterACycle() {
        let bumped = Progression.bumpedTrainingMaxKg(currentTrainingMaxKg: 140, lift: .squat)
        #expect(bumped == 145.0)
    }

    @Test func deadliftTrainingMaxBumpsBy5kgAfterACycle() {
        let bumped = Progression.bumpedTrainingMaxKg(currentTrainingMaxKg: 160, lift: .deadlift)
        #expect(bumped == 165.0)
    }

    // MARK: - Linear progression

    @Test func benchNextLinearWeightAddsDefault2Point5kg() {
        let next = Progression.nextLinearWeightKg(currentWeightKg: 60, lift: .bench)
        #expect(next == 62.5)
    }

    @Test func squatNextLinearWeightAddsDefault5kg() {
        let next = Progression.nextLinearWeightKg(currentWeightKg: 100, lift: .squat)
        #expect(next == 105.0)
    }

    @Test func deadliftNextLinearWeightAddsDefault5kg() {
        let next = Progression.nextLinearWeightKg(currentWeightKg: 120, lift: .deadlift)
        #expect(next == 125.0)
    }

    @Test func linearProgressionAcceptsACustomIncrement() {
        let next = Progression.nextLinearWeightKg(currentWeightKg: 100, lift: .squat, upperIncrementKg: 2.5, lowerIncrementKg: 10)
        #expect(next == 110.0)
    }
}
