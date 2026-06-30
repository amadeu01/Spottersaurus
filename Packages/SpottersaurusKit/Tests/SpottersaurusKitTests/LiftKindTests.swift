//
//  LiftKindTests.swift
//  SpottersaurusKitTests
//
//  Locks the bar-tracking contract that selects the detection path:
//  squat is back-loaded (wrist static), bench / deadlift are wrist-tracked.
//

import XCTest
@testable import SpottersaurusKit

final class LiftKindTests: XCTestCase {

    func testSquatIsBackLoaded() {
        XCTAssertEqual(LiftKind.squat.barTracking, .backLoaded)
        XCTAssertFalse(LiftKind.squat.usesVelocityPath)
    }

    func testBenchAndDeadliftAreWristTracked() {
        XCTAssertEqual(LiftKind.bench.barTracking, .wristTracked)
        XCTAssertEqual(LiftKind.deadlift.barTracking, .wristTracked)
        XCTAssertTrue(LiftKind.bench.usesVelocityPath)
        XCTAssertTrue(LiftKind.deadlift.usesVelocityPath)
    }

    func testAllLiftsHaveStableRawValues() {
        // Raw values are persisted / sent over the wire — guard against drift.
        XCTAssertEqual(LiftKind.squat.rawValue, "squat")
        XCTAssertEqual(LiftKind.bench.rawValue, "bench")
        XCTAssertEqual(LiftKind.deadlift.rawValue, "deadlift")
        XCTAssertEqual(LiftKind.accessory.rawValue, "accessory")
    }
}
