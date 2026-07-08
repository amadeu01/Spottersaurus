//
//  ModelTests.swift
//  SpottersaurusKitTests
//
//  Exercises the SwiftData schema against an in-memory, CloudKit-off container:
//  insert/fetch round-trip, cascade delete, Epley math, and the preset seeders.
//

import XCTest
import SwiftData
@testable import SpottersaurusKit

@MainActor
final class ModelTests: XCTestCase {

    /// A fresh in-memory container per test — no disk, no CloudKit.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try makeModelContainer(inMemory: true, cloudKit: false)
        return (container, ModelContext(container))
    }

    func testCloudKitModelContainerBuilds() throws {
        _ = try makeModelContainer(cloudKit: true)
    }

    // MARK: insert / fetch round-trip

    func testProgramGraphRoundTrips() throws {
        let (_, context) = try makeContext()

        let squat = Exercise(name: "Back Squat", kind: .squat)
        let program = Program(name: "Test Program", rule: .custom)
        let day = ProgramDay(name: "Day 1", sortIndex: 0)
        let setA = PlannedSet(exercise: squat, targetReps: 5, load: .absolute(kg: 100), sortIndex: 0)
        let setB = PlannedSet(exercise: squat, targetReps: 3, load: .percentOfTrainingMax(percent: 90), isAMRAP: true, sortIndex: 1)
        day.plannedSets = [setB, setA] // intentionally out of order to prove sortIndex wins
        program.days = [day]

        context.insert(program)
        try context.save()

        let programs = try context.fetch(FetchDescriptor<Program>())
        XCTAssertEqual(programs.count, 1)
        let fetched = try XCTUnwrap(programs.first)
        XCTAssertEqual(fetched.orderedDays.count, 1)

        let fetchedDay = try XCTUnwrap(fetched.orderedDays.first)
        let ordered = fetchedDay.orderedSets
        XCTAssertEqual(ordered.map(\.sortIndex), [0, 1])
        XCTAssertEqual(ordered.first?.targetReps, 5)
        XCTAssertEqual(ordered.first?.load, .absolute(kg: 100))
        XCTAssertEqual(ordered.last?.isAMRAP, true)
        XCTAssertEqual(ordered.last?.exercise?.kind, .squat)
    }

    // MARK: cascade delete

    func testDeletingProgramCascadesDaysAndSetsButKeepsExercise() throws {
        let (_, context) = try makeContext()

        let bench = Exercise(name: "Bench Press", kind: .bench)
        let program = Program(name: "Cascade", rule: .linear)
        let day = ProgramDay(name: "Bench Day", sortIndex: 0)
        day.plannedSets = [
            PlannedSet(exercise: bench, targetReps: 5, load: .absolute(kg: 80), sortIndex: 0),
            PlannedSet(exercise: bench, targetReps: 5, load: .absolute(kg: 80), sortIndex: 1),
        ]
        program.days = [day]
        context.insert(program)
        context.insert(bench)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDay>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedSet>()), 2)

        context.delete(program)
        try context.save()

        // Cascade removed the day and its sets…
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Program>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDay>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedSet>()), 0)
        // …but the shared exercise survives (nullify, not cascade).
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testDeletingSessionCascadesSetsAndRepMetrics() throws {
        let (_, context) = try makeContext()

        let dead = Exercise(name: "Deadlift", kind: .deadlift)
        let session = WorkoutSession(source: .watch)
        let set = CompletedSet(exercise: dead, weightKg: 180, repsPerformed: 3)
        set.repMetrics = [
            RepMetric(repIndex: 0, concentricSeconds: 1.1, peakVelocityMS: 0.5, meanVelocityMS: 0.35),
            RepMetric(repIndex: 1, concentricSeconds: 1.4, peakVelocityMS: 0.4, meanVelocityMS: 0.28, flaggedStall: true),
        ]
        session.completedSets = [set]
        context.insert(session)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSet>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RepMetric>()), 2)

        context.delete(session)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompletedSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RepMetric>()), 0)
    }

    // MARK: Epley

    func testEpleyE1RM() {
        // 100 kg × 5 → 100 × (1 + 5/30) = 116.666…
        XCTAssertEqual(Epley.e1RM(weightKg: 100, reps: 5), 116.7, accuracy: 0.05)
        // Literal Epley applies the +1/30 even at one rep: 140 × (1 + 1/30) = 144.67.
        XCTAssertEqual(Epley.e1RM(weightKg: 140, reps: 1), 144.667, accuracy: 0.01)
        // Guard against zero / negative reps.
        XCTAssertEqual(Epley.e1RM(weightKg: 100, reps: 0), 0, accuracy: 0.0001)
    }

    func testCompletedSetExposesEpleyE1RM() {
        let set = CompletedSet(exercise: nil, weightKg: 100, repsPerformed: 5)
        XCTAssertEqual(set.estimatedOneRepMaxKg, 116.7, accuracy: 0.05)
    }

    // MARK: preset seeders

    private func sampleMaxes() -> [UserMaxes] {
        [
            UserMaxes(lift: .squat, trainingMaxKg: 180, oneRepMaxKg: 200),
            UserMaxes(lift: .bench, trainingMaxKg: 120, oneRepMaxKg: 135),
            UserMaxes(lift: .deadlift, trainingMaxKg: 220, oneRepMaxKg: 245),
        ]
    }

    func testFiveThreeOnePresetStructure() {
        let program = Program.fiveThreeOne(maxes: sampleMaxes())
        XCTAssertEqual(program.rule, .fivethreeone)
        XCTAssertEqual(program.orderedDays.count, 3)
        XCTAssertEqual(program.orderedDays.map { $0.orderedSets.first?.exercise?.kind },
                       [.squat, .bench, .deadlift])

        for day in program.orderedDays {
            let sets = day.orderedSets
            XCTAssertEqual(sets.count, 3)
            XCTAssertEqual(sets.map(\.targetReps), [5, 5, 5])
            XCTAssertEqual(sets.map(\.isAMRAP), [false, false, true])
            XCTAssertEqual(sets.map(\.load), [
                .percentOfTrainingMax(percent: 65),
                .percentOfTrainingMax(percent: 75),
                .percentOfTrainingMax(percent: 85),
            ])
        }

        // Percentage loads resolve against the lift's training max.
        let squatTopSet = program.orderedDays[0].orderedSets[2]
        XCTAssertEqual(squatTopSet.resolvedWeightKg(trainingMaxKg: 180), 153, accuracy: 0.0001) // 85% of 180
    }

    func testLinearProgressionPresetStructure() {
        let program = Program.linearProgression(maxes: sampleMaxes())
        XCTAssertEqual(program.rule, .linear)
        XCTAssertEqual(program.orderedDays.count, 3)

        for day in program.orderedDays {
            let sets = day.orderedSets
            XCTAssertEqual(sets.count, 5)
            XCTAssertEqual(sets.map(\.targetReps), Array(repeating: 5, count: 5))
            XCTAssertTrue(sets.allSatisfy { !$0.isAMRAP })
        }

        // Squat starts at 60% of TM 180 = 108, rounded to the 2.5 kg plate = 107.5.
        let squatSet = program.orderedDays[0].orderedSets[0]
        XCTAssertEqual(squatSet.load, .absolute(kg: 107.5))
    }

    func testRoundToPlate() {
        XCTAssertEqual(Program.roundToPlate(108), 107.5, accuracy: 0.0001)   // 43.2 → 43
        XCTAssertEqual(Program.roundToPlate(106.24), 105, accuracy: 0.0001)  // 42.496 → 42
        XCTAssertEqual(Program.roundToPlate(106.26), 107.5, accuracy: 0.0001) // 42.504 → 43
    }
}
