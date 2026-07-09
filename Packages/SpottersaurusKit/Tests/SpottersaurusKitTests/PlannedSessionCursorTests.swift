//
//  PlannedSessionCursorTests.swift
//  SpottersaurusKitTests
//
//  Headless tests for the pure multi-set cursor (Phase 0.2, M1a). Covers the
//  "everything is bench" root cause directly: no bench/weight fallback
//  anywhere, sets always run in `sortIndex` order regardless of input order,
//  and advancing past the last set is well-defined rather than crashing.
//

import XCTest
@testable import SpottersaurusKit

final class PlannedSessionCursorTests: XCTestCase {

    private func makeSet(_ name: String, sortIndex: Int) -> PlannedSetEnvelope {
        PlannedSetEnvelope(
            lift: .bench,
            exerciseName: name,
            targetReps: 5,
            weightKg: 60,
            sortIndex: sortIndex
        )
    }

    // MARK: - Ordering

    func test_setsAreSortedBySortIndex_regardlessOfInputOrder() {
        let shuffled = [
            makeSet("C", sortIndex: 2),
            makeSet("A", sortIndex: 0),
            makeSet("B", sortIndex: 1)
        ]
        let cursor = PlannedSessionCursor(sets: shuffled)
        XCTAssertEqual(cursor.orderedSets.map(\.exerciseName), ["A", "B", "C"])
    }

    func test_initFromSession_sortsBySortIndex() {
        let session = PlannedSessionEnvelope(
            programName: "Program",
            dayName: "Day",
            sets: [makeSet("Second", sortIndex: 1), makeSet("First", sortIndex: 0)]
        )
        let cursor = PlannedSessionCursor(session: session)
        XCTAssertEqual(cursor.orderedSets.map(\.exerciseName), ["First", "Second"])
    }

    // MARK: - First / middle / last

    func test_firstSet_currentAndNext() {
        let cursor = PlannedSessionCursor(sets: [
            makeSet("A", sortIndex: 0),
            makeSet("B", sortIndex: 1),
            makeSet("C", sortIndex: 2)
        ])
        XCTAssertEqual(cursor.setIndex, 0)
        XCTAssertEqual(cursor.setCount, 3)
        XCTAssertEqual(cursor.current?.exerciseName, "A")
        XCTAssertEqual(cursor.next?.exerciseName, "B")
        XCTAssertTrue(cursor.hasNext)
        XCTAssertFalse(cursor.isLast)
        XCTAssertFalse(cursor.isFinished)
    }

    func test_middleSet_currentAndNext() {
        var cursor = PlannedSessionCursor(sets: [
            makeSet("A", sortIndex: 0),
            makeSet("B", sortIndex: 1),
            makeSet("C", sortIndex: 2)
        ])
        cursor.advance()
        XCTAssertEqual(cursor.setIndex, 1)
        XCTAssertEqual(cursor.current?.exerciseName, "B")
        XCTAssertEqual(cursor.next?.exerciseName, "C")
        XCTAssertTrue(cursor.hasNext)
        XCTAssertFalse(cursor.isLast)
        XCTAssertFalse(cursor.isFinished)
    }

    func test_lastSet_currentHasNoNext_isLastTrue() {
        var cursor = PlannedSessionCursor(sets: [
            makeSet("A", sortIndex: 0),
            makeSet("B", sortIndex: 1),
            makeSet("C", sortIndex: 2)
        ])
        cursor.advance()
        cursor.advance()
        XCTAssertEqual(cursor.setIndex, 2)
        XCTAssertEqual(cursor.current?.exerciseName, "C")
        XCTAssertNil(cursor.next)
        XCTAssertFalse(cursor.hasNext)
        XCTAssertTrue(cursor.isLast)
        XCTAssertFalse(cursor.isFinished)
    }

    // MARK: - Advancement / terminal behavior

    func test_advance_progressesThroughEachSetInOrder() {
        var cursor = PlannedSessionCursor(sets: [
            makeSet("A", sortIndex: 0),
            makeSet("B", sortIndex: 1),
            makeSet("C", sortIndex: 2)
        ])
        var seen: [String] = []
        while let current = cursor.current {
            seen.append(current.exerciseName)
            cursor.advance()
        }
        XCTAssertEqual(seen, ["A", "B", "C"])
    }

    func test_advancePastLastSet_currentBecomesNil_isFinishedTrue() {
        var cursor = PlannedSessionCursor(sets: [
            makeSet("A", sortIndex: 0),
            makeSet("B", sortIndex: 1)
        ])
        cursor.advance()
        cursor.advance()
        XCTAssertNil(cursor.current)
        XCTAssertNil(cursor.next)
        XCTAssertTrue(cursor.isFinished)
        XCTAssertFalse(cursor.isLast)
        XCTAssertFalse(cursor.hasNext)
    }

    func test_advanceRepeatedlyPastLastSet_clampsAndStaysFinished() {
        var cursor = PlannedSessionCursor(sets: [makeSet("A", sortIndex: 0)])
        cursor.advance()
        XCTAssertTrue(cursor.isFinished)
        let finishedIndex = cursor.setIndex

        cursor.advance()
        cursor.advance()
        XCTAssertEqual(cursor.setIndex, finishedIndex, "advance() past the end should clamp, not overshoot")
        XCTAssertTrue(cursor.isFinished)
        XCTAssertNil(cursor.current)
    }

    // MARK: - Empty session (the honest "no session" state — no bench fallback)

    func test_emptySession_currentIsNil_setCountZero_noCrash() {
        let cursor = PlannedSessionCursor(sets: [])
        XCTAssertNil(cursor.current)
        XCTAssertNil(cursor.next)
        XCTAssertEqual(cursor.setCount, 0)
        XCTAssertEqual(cursor.setIndex, 0)
        XCTAssertTrue(cursor.isFinished)
        XCTAssertFalse(cursor.isLast)
        XCTAssertFalse(cursor.hasNext)
    }

    func test_emptySession_advanceIsNoOp() {
        var cursor = PlannedSessionCursor(sets: [])
        cursor.advance()
        XCTAssertEqual(cursor.setIndex, 0)
        XCTAssertNil(cursor.current)
        XCTAssertTrue(cursor.isFinished)
    }

    // MARK: - Single-set session

    func test_singleSetSession_isLastImmediately_noNext() {
        let cursor = PlannedSessionCursor(sets: [makeSet("Only", sortIndex: 0)])
        XCTAssertEqual(cursor.setCount, 1)
        XCTAssertEqual(cursor.current?.exerciseName, "Only")
        XCTAssertNil(cursor.next)
        XCTAssertFalse(cursor.hasNext)
        XCTAssertTrue(cursor.isLast)
        XCTAssertFalse(cursor.isFinished)
    }

    func test_singleSetSession_advanceFinishes() {
        var cursor = PlannedSessionCursor(sets: [makeSet("Only", sortIndex: 0)])
        cursor.advance()
        XCTAssertNil(cursor.current)
        XCTAssertTrue(cursor.isFinished)
    }
}
