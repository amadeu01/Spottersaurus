//
//  SessionOverrideTests.swift
//  SpottersaurusKitTests
//
//  TDD coverage for the ephemeral Session Override editor's pure model
//  (Phase 0.2 M2). `SessionOverride` never touches SwiftData / the Program —
//  it only rewrites a resolved `PlannedSessionEnvelope` copy, so these tests
//  exercise `apply(to:)` directly against envelopes (and, at the bottom,
//  confirm the source `Program`/`PlannedSet` models are untouched).
//

import XCTest
@testable import SpottersaurusKit

final class SessionOverrideTests: XCTestCase {

    private func makeBase() -> PlannedSessionEnvelope {
        PlannedSessionEnvelope(
            programName: "5/3/1",
            dayName: "Bench Day",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                PlannedSetEnvelope(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 80, isAMRAP: false, restSeconds: 180, sortIndex: 0),
                PlannedSetEnvelope(lift: .accessory, exerciseName: "Barbell Row", targetReps: 8, weightKg: 60, isAMRAP: false, restSeconds: 120, sortIndex: 1),
                PlannedSetEnvelope(lift: .bench, exerciseName: "Close Grip Bench", targetReps: 10, weightKg: 40, isAMRAP: true, restSeconds: 90, sortIndex: 2),
            ]
        )
    }

    // MARK: Empty override is identity

    func testEmptyOverrideReturnsBaseUnchanged() {
        let base = makeBase()

        let adjusted = SessionOverride.empty.apply(to: base)

        XCTAssertEqual(adjusted, base)
    }

    func testDefaultInitOverrideIsEmpty() {
        let override = SessionOverride()
        let base = makeBase()
        XCTAssertTrue(override.isEmpty)
        XCTAssertEqual(override.apply(to: base), base)
    }

    /// An override entry present in the dictionary but with every field nil
    /// (`SetOverride.empty`) must still behave as identity for that set.
    func testEmptyPerSetOverrideEntryIsIdentityForThatSet() {
        let base = makeBase()
        let firstID = base.sets[0].id
        let override = SessionOverride(setOverrides: [firstID: .empty])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted, base)
    }

    // MARK: Per-field overrides apply to the right set only

    func testWeightOverrideAppliesOnlyToTargetedSet() {
        let base = makeBase()
        let targetID = base.sets[0].id
        let override = SessionOverride(setOverrides: [targetID: SetOverride(weightKg: 85)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets[0].weightKg, 85)
        // Everything else about the overridden set is untouched.
        XCTAssertEqual(adjusted.sets[0].targetReps, base.sets[0].targetReps)
        XCTAssertEqual(adjusted.sets[0].lift, base.sets[0].lift)
        XCTAssertEqual(adjusted.sets[0].restSeconds, base.sets[0].restSeconds)
        XCTAssertEqual(adjusted.sets[0].isAMRAP, base.sets[0].isAMRAP)
        // Untouched sets pass through byte-for-byte.
        XCTAssertEqual(adjusted.sets[1], base.sets[1])
        XCTAssertEqual(adjusted.sets[2], base.sets[2])
    }

    func testTargetRepsOverrideAppliesOnlyToTargetedSet() {
        let base = makeBase()
        let targetID = base.sets[1].id
        let override = SessionOverride(setOverrides: [targetID: SetOverride(targetReps: 12)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets[1].targetReps, 12)
        XCTAssertEqual(adjusted.sets[0], base.sets[0])
        XCTAssertEqual(adjusted.sets[2], base.sets[2])
    }

    func testRestSecondsOverrideAppliesOnlyToTargetedSet() {
        let base = makeBase()
        let targetID = base.sets[2].id
        let override = SessionOverride(setOverrides: [targetID: SetOverride(restSeconds: 240)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets[2].restSeconds, 240)
        XCTAssertEqual(adjusted.sets[0], base.sets[0])
        XCTAssertEqual(adjusted.sets[1], base.sets[1])
    }

    func testIsAMRAPOverrideAppliesOnlyToTargetedSet() {
        let base = makeBase()
        let targetID = base.sets[0].id
        let override = SessionOverride(setOverrides: [targetID: SetOverride(isAMRAP: true)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets[0].isAMRAP, true)
        XCTAssertEqual(adjusted.sets[1], base.sets[1])
        XCTAssertEqual(adjusted.sets[2], base.sets[2])
    }

    func testLiftOverrideAppliesOnlyToTargetedSet() {
        let base = makeBase()
        let targetID = base.sets[1].id
        let override = SessionOverride(setOverrides: [targetID: SetOverride(lift: .deadlift)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets[1].lift, .deadlift)
        XCTAssertEqual(adjusted.sets[0], base.sets[0])
        XCTAssertEqual(adjusted.sets[2], base.sets[2])
    }

    /// Multiple fields on the same set combine.
    func testMultipleFieldOverridesCombineOnSameSet() {
        let base = makeBase()
        let targetID = base.sets[0].id
        let override = SessionOverride(setOverrides: [
            targetID: SetOverride(targetReps: 3, weightKg: 90, restSeconds: 200, isAMRAP: true),
        ])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets[0].targetReps, 3)
        XCTAssertEqual(adjusted.sets[0].weightKg, 90)
        XCTAssertEqual(adjusted.sets[0].restSeconds, 200)
        XCTAssertEqual(adjusted.sets[0].isAMRAP, true)
        XCTAssertEqual(adjusted.sets[0].lift, base.sets[0].lift)
    }

    /// Overrides on multiple different sets apply independently.
    func testOverridesOnMultipleSetsApplyIndependently() {
        let base = makeBase()
        let override = SessionOverride(setOverrides: [
            base.sets[0].id: SetOverride(weightKg: 85),
            base.sets[2].id: SetOverride(targetReps: 15),
        ])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets[0].weightKg, 85)
        XCTAssertEqual(adjusted.sets[1], base.sets[1])
        XCTAssertEqual(adjusted.sets[2].targetReps, 15)
    }

    // MARK: Set order/count preserved

    func testSetOrderAndCountPreserved() {
        let base = makeBase()
        let override = SessionOverride(setOverrides: [base.sets[1].id: SetOverride(weightKg: 65)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.sets.count, base.sets.count)
        XCTAssertEqual(adjusted.sets.map(\.id), base.sets.map(\.id))
        XCTAssertEqual(adjusted.sets.map(\.sortIndex), base.sets.map(\.sortIndex))
    }

    /// Session-level metadata (id/programName/dayName/createdAt) is untouched
    /// by a per-set override.
    func testSessionMetadataUntouchedByOverride() {
        let base = makeBase()
        let override = SessionOverride(setOverrides: [base.sets[0].id: SetOverride(weightKg: 85)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted.id, base.id)
        XCTAssertEqual(adjusted.programName, base.programName)
        XCTAssertEqual(adjusted.dayName, base.dayName)
        XCTAssertEqual(adjusted.createdAt, base.createdAt)
    }

    /// An override keyed by an id that doesn't match any set in the envelope
    /// is simply inert (defensive — e.g. a stale editor state after the
    /// underlying program day changed).
    func testOverrideForUnknownSetIDIsInert() {
        let base = makeBase()
        let override = SessionOverride(setOverrides: [UUID(): SetOverride(weightKg: 999)])

        let adjusted = override.apply(to: base)

        XCTAssertEqual(adjusted, base)
    }

    // MARK: Program/PlannedSet are never mutated

    /// Applying an override only ever rewrites the envelope copy; it must
    /// never reach back into the SwiftData `Program`/`PlannedSet` models the
    /// base envelope was resolved from.
    func testApplyingOverrideDoesNotMutateSourceProgramModels() {
        let exercise = Exercise(name: "Bench Press", kind: .bench)
        let program = Program(name: "Upper", rule: .custom)
        let day = ProgramDay(name: "Day 1")
        let plannedSet = PlannedSet(exercise: exercise, targetReps: 5, load: .absolute(kg: 80), restSeconds: 180)
        day.plannedSets = [plannedSet]
        program.days = [day]
        let maxes: [UserMaxes] = []

        let base = PlannedSessionEnvelope.make(program: program, day: day, maxes: maxes)
        let override = SessionOverride(setOverrides: [plannedSet.id: SetOverride(lift: .deadlift, targetReps: 1, weightKg: 999, restSeconds: 30, isAMRAP: true)])
        _ = override.apply(to: base)

        XCTAssertEqual(plannedSet.targetReps, 5)
        XCTAssertEqual(plannedSet.restSeconds, 180)
        XCTAssertEqual(plannedSet.isAMRAP, false)
        XCTAssertEqual(plannedSet.exercise?.kind, .bench)
        if case .absolute(let kg) = plannedSet.load {
            XCTAssertEqual(kg, 80)
        } else {
            XCTFail("expected .absolute load")
        }
    }
}
