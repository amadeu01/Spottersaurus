//
//  LiftKindTests.swift
//  SpottersaurusKitTests
//
//  Locks the bar-tracking contract that selects the detection path: squat is
//  back-loaded (wrist static), bench / deadlift are wrist-tracked. Also locks
//  the ADR 0009 split between "computes velocity" and "velocity drives
//  alerts" — squat now computes velocity (wrist rides the bar) but must not
//  let it drive the trigger, pending validation.
//

import XCTest
@testable import SpottersaurusKit

final class LiftKindTests: XCTestCase {

    func testSquatIsBackLoaded() {
        XCTAssertEqual(LiftKind.squat.barTracking, .backLoaded)
        XCTAssertFalse(LiftKind.squat.velocityDrivesAlerts)
    }

    func testBenchAndDeadliftAreWristTracked() {
        XCTAssertEqual(LiftKind.bench.barTracking, .wristTracked)
        XCTAssertEqual(LiftKind.deadlift.barTracking, .wristTracked)
        XCTAssertTrue(LiftKind.bench.velocityDrivesAlerts)
        XCTAssertTrue(LiftKind.deadlift.velocityDrivesAlerts)
    }

    /// ADR 0009: squat's wrist rides the bar, so velocity is now computed for
    /// every lift — including squat — even though squat's trigger stays
    /// tempo/HR.
    func testAllLiftsComputeVelocity() {
        XCTAssertTrue(LiftKind.squat.computesVelocity, "squat's wrist rides the bar; velocity is now meaningful (ADR 0009)")
        XCTAssertTrue(LiftKind.bench.computesVelocity)
        XCTAssertTrue(LiftKind.deadlift.computesVelocity)
        XCTAssertTrue(LiftKind.accessory.computesVelocity)
    }

    /// Only bench/deadlift let a computed velocity number drive the alert
    /// trigger; squat computes velocity but never triggers on it (ADR 0009).
    func testOnlyBenchAndDeadliftVelocityDrivesAlerts() {
        XCTAssertFalse(LiftKind.squat.velocityDrivesAlerts)
        XCTAssertTrue(LiftKind.bench.velocityDrivesAlerts)
        XCTAssertTrue(LiftKind.deadlift.velocityDrivesAlerts)
        XCTAssertTrue(LiftKind.accessory.velocityDrivesAlerts)
    }

    /// The deprecated alias must still mirror `velocityDrivesAlerts` exactly,
    /// so any lingering external caller sees unchanged behavior.
    func testDeprecatedUsesVelocityPathAliasesVelocityDrivesAlerts() {
        for lift in LiftKind.allCases {
            XCTAssertEqual(lift.usesVelocityPath, lift.velocityDrivesAlerts, "\(lift) alias must match velocityDrivesAlerts")
        }
    }

    func testAllLiftsHaveStableRawValues() {
        // Raw values are persisted / sent over the wire — guard against drift.
        XCTAssertEqual(LiftKind.squat.rawValue, "squat")
        XCTAssertEqual(LiftKind.bench.rawValue, "bench")
        XCTAssertEqual(LiftKind.deadlift.rawValue, "deadlift")
        XCTAssertEqual(LiftKind.accessory.rawValue, "accessory")
    }
}
