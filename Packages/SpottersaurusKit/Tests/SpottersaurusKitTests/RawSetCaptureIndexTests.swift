//
//  RawSetCaptureIndexTests.swift
//  SpottersaurusKitTests
//
//  Locks the pure grouping (workout → exercise → set) + keep-last-N-workouts
//  retention logic behind PRC-3 (ADR 0008). Device-side file I/O is a thin
//  adapter over this and carries no swift-test coverage.
//

import XCTest
@testable import SpottersaurusKit

final class RawSetCaptureIndexTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_752_000_000)

    private func id(
        session: UUID,
        set: UUID = UUID(),
        setIndex: Int = 0,
        setCount: Int = 3,
        lift: LiftKind = .bench,
        armedAtOffset: TimeInterval,
        fileName: String? = nil
    ) -> RawSetCaptureIdentity {
        RawSetCaptureIdentity(
            sessionID: session,
            setID: set,
            setIndex: setIndex,
            setCount: setCount,
            lift: lift,
            armedAt: base.addingTimeInterval(armedAtOffset),
            fileName: fileName ?? "\(set.uuidString).plist"
        )
    }

    // MARK: Grouping

    func testGroupsWorkoutExerciseSet() {
        let session = UUID()
        let benchSet0 = UUID()
        let benchSet1 = UUID()
        let squatSet0 = UUID()

        let index = RawSetCaptureIndex([
            id(session: session, set: benchSet0, setIndex: 0, lift: .bench, armedAtOffset: 0),
            id(session: session, set: benchSet1, setIndex: 1, lift: .bench, armedAtOffset: 120),
            id(session: session, set: squatSet0, setIndex: 0, lift: .squat, armedAtOffset: 600)
        ])

        let workouts = index.workouts
        XCTAssertEqual(workouts.count, 1)
        let workout = workouts[0]
        XCTAssertEqual(workout.sessionID, session)
        XCTAssertEqual(workout.exercises.count, 2)

        // Exercises are chronological: bench (first at t=0) before squat (t=600).
        XCTAssertEqual(workout.exercises[0].lift, .bench)
        XCTAssertEqual(workout.exercises[1].lift, .squat)

        // Bench has two sets ordered by setIndex.
        let benchSets = workout.exercises[0].sets
        XCTAssertEqual(benchSets.map(\.setID), [benchSet0, benchSet1])
        XCTAssertEqual(benchSets.map(\.setIndex), [0, 1])
        XCTAssertEqual(benchSets.map { $0.captures.count }, [1, 1])
    }

    func testWorkoutsSortedNewestFirst() {
        let older = UUID()
        let newer = UUID()
        let index = RawSetCaptureIndex([
            id(session: older, armedAtOffset: 0),
            id(session: newer, armedAtOffset: 10_000)
        ])

        XCTAssertEqual(index.workouts.map(\.sessionID), [newer, older])
    }

    func testWorkoutRecencyIsLatestCapture() {
        let a = UUID()
        let b = UUID()
        // Session A's newest set is later than session B's newest set, even
        // though A also has an early set.
        let index = RawSetCaptureIndex([
            id(session: a, set: UUID(), armedAtOffset: 0),
            id(session: a, set: UUID(), armedAtOffset: 5_000),
            id(session: b, set: UUID(), armedAtOffset: 3_000)
        ])
        XCTAssertEqual(index.workouts.map(\.sessionID), [a, b])
    }

    // MARK: Per-set listing

    func testCapturesForSetNewestFirst() {
        let session = UUID()
        let set = UUID()
        let index = RawSetCaptureIndex([
            id(session: session, set: set, armedAtOffset: 0, fileName: "first.plist"),
            id(session: session, set: set, armedAtOffset: 100, fileName: "second.plist")
        ])

        let captures = index.captures(forSet: set)
        XCTAssertEqual(captures.map(\.fileName), ["second.plist", "first.plist"])
    }

    func testCapturesForUnknownSetIsEmpty() {
        let index = RawSetCaptureIndex([id(session: UUID(), armedAtOffset: 0)])
        XCTAssertTrue(index.captures(forSet: UUID()).isEmpty)
    }

    // MARK: Insert / dedupe

    func testInsertDedupesByFileName() {
        var index = RawSetCaptureIndex()
        let set = UUID()
        let session = UUID()
        index.insert(id(session: session, set: set, setCount: 3, armedAtOffset: 0, fileName: "cap.plist"))
        index.insert(id(session: session, set: set, setCount: 5, armedAtOffset: 100, fileName: "cap.plist"))

        XCTAssertEqual(index.identities.count, 1)
        // The later insert replaced the earlier one (updated setCount/armedAt).
        XCTAssertEqual(index.identities[0].setCount, 5)
        XCTAssertEqual(index.identities[0].armedAt, base.addingTimeInterval(100))
    }

    // MARK: Manual delete

    func testRemoveByFileName() {
        var index = RawSetCaptureIndex([
            id(session: UUID(), armedAtOffset: 0, fileName: "keep.plist"),
            id(session: UUID(), armedAtOffset: 1, fileName: "drop.plist")
        ])
        let removed = index.remove(fileName: "drop.plist")
        XCTAssertEqual(removed?.fileName, "drop.plist")
        XCTAssertEqual(index.identities.map(\.fileName), ["keep.plist"])
        XCTAssertNil(index.remove(fileName: "missing.plist"))
    }

    func testRemoveSetDropsAllItsCaptures() {
        let session = UUID()
        let set = UUID()
        var index = RawSetCaptureIndex([
            id(session: session, set: set, armedAtOffset: 0, fileName: "a.plist"),
            id(session: session, set: set, armedAtOffset: 1, fileName: "b.plist"),
            id(session: session, set: UUID(), armedAtOffset: 2, fileName: "c.plist")
        ])
        let removed = index.removeSet(set)
        XCTAssertEqual(Set(removed.map(\.fileName)), ["a.plist", "b.plist"])
        XCTAssertEqual(index.identities.map(\.fileName), ["c.plist"])
    }

    // MARK: Retention

    func testPruneKeepsLastNWorkouts() {
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        var index = RawSetCaptureIndex([
            id(session: s1, set: UUID(), armedAtOffset: 0, fileName: "s1.plist"),
            id(session: s2, set: UUID(), armedAtOffset: 1_000, fileName: "s2.plist"),
            id(session: s3, set: UUID(), armedAtOffset: 2_000, fileName: "s3.plist")
        ])

        let doomed = index.identitiesToPrune(keepingLastSessions: 2)
        XCTAssertEqual(doomed.map(\.fileName), ["s1.plist"])

        let pruned = index.prune(keepingLastSessions: 2)
        XCTAssertEqual(pruned.map(\.fileName), ["s1.plist"])
        XCTAssertEqual(Set(index.workouts.map(\.sessionID)), [s2, s3])
    }

    func testPrunePrunesAllOfAnOldWorkoutsSets() {
        let old = UUID()
        let new = UUID()
        var index = RawSetCaptureIndex([
            id(session: old, set: UUID(), setIndex: 0, armedAtOffset: 0, fileName: "old0.plist"),
            id(session: old, set: UUID(), setIndex: 1, armedAtOffset: 100, fileName: "old1.plist"),
            id(session: new, set: UUID(), armedAtOffset: 10_000, fileName: "new0.plist")
        ])
        let pruned = index.prune(keepingLastSessions: 1)
        XCTAssertEqual(Set(pruned.map(\.fileName)), ["old0.plist", "old1.plist"])
        XCTAssertEqual(index.identities.map(\.fileName), ["new0.plist"])
    }

    func testPruneKeepingMoreThanCountPrunesNothing() {
        var index = RawSetCaptureIndex([
            id(session: UUID(), armedAtOffset: 0),
            id(session: UUID(), armedAtOffset: 1)
        ])
        XCTAssertTrue(index.identitiesToPrune(keepingLastSessions: 5).isEmpty)
        XCTAssertTrue(index.prune(keepingLastSessions: 5).isEmpty)
        XCTAssertEqual(index.identities.count, 2)
    }

    func testPruneKeepingZeroPrunesEverything() {
        let index = RawSetCaptureIndex([
            id(session: UUID(), armedAtOffset: 0),
            id(session: UUID(), armedAtOffset: 1)
        ])
        XCTAssertEqual(index.identitiesToPrune(keepingLastSessions: 0).count, 2)
    }

    // MARK: Codable round-trip (on-disk sidecar contract)

    func testIndexCodableRoundTrip() throws {
        let index = RawSetCaptureIndex([
            id(session: UUID(), set: UUID(), setIndex: 1, lift: .deadlift, armedAtOffset: 42, fileName: "x.plist")
        ])
        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(RawSetCaptureIndex.self, from: data)
        XCTAssertEqual(decoded, index)
    }
}
