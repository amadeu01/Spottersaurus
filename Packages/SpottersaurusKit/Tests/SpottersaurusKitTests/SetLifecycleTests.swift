//
//  SetLifecycleTests.swift
//  SpottersaurusKitTests
//
//  Headless, hardware-free tests for the Phase 4c set-lifecycle state machine.
//  No CoreMotion / HealthKit / SwiftUI / WorkoutKit — time is injected, never
//  wall-clock, so every transition here is deterministic.
//

import XCTest
@testable import SpottersaurusKit

final class SetLifecycleTests: XCTestCase {

    func test_initialStateIsIdleWithZeroRepsAndNoAlert() {
        let controller = SetLifecycleController()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.repCount, 0)
        XCTAssertEqual(controller.alertStage, .none)
    }

    func test_armFromIdleTransitionsToArmed() {
        var controller = SetLifecycleController()
        controller.arm()
        XCTAssertEqual(controller.state, .armed)
    }

    func test_repCompletedWhileArmedTransitionsToRepping_andIncrementsCount() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        XCTAssertEqual(controller.state, .repping)
        XCTAssertEqual(controller.repCount, 1)
    }

    func test_repCompletedWhileIdleIsIgnored() {
        var controller = SetLifecycleController()
        controller.repCompleted()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.repCount, 0)
    }

    func test_multipleRepsIncrementCount_stateStaysRepping() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.repCompleted()
        controller.repCompleted()
        XCTAssertEqual(controller.state, .repping)
        XCTAssertEqual(controller.repCount, 3)
    }

    func test_autoRackWhileReppingTransitionsToRacked() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.autoRack()
        XCTAssertEqual(controller.state, .racked)
        XCTAssertEqual(controller.repCount, 1)
    }

    func test_autoRackWhileNotReppingIsIgnored() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.autoRack()
        XCTAssertEqual(controller.state, .armed)
    }

    func test_restTickWhileRackedTransitionsToResting() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.autoRack()
        controller.restTick(elapsed: 0)
        XCTAssertEqual(controller.state, .resting)
    }

    func test_restTickBelowTargetDurationStaysResting() {
        var controller = SetLifecycleController(restSeconds: 90)
        controller.arm()
        controller.repCompleted()
        controller.autoRack()
        controller.restTick(elapsed: 0)
        controller.restTick(elapsed: 30)
        controller.restTick(elapsed: 89)
        XCTAssertEqual(controller.state, .resting)
    }

    func test_restTickReachingTargetDurationTransitionsToComplete() {
        var controller = SetLifecycleController(restSeconds: 90)
        controller.arm()
        controller.repCompleted()
        controller.autoRack()
        controller.restTick(elapsed: 0)
        controller.restTick(elapsed: 90)
        XCTAssertEqual(controller.state, .complete)
    }

    func test_armAfterCompleteStartsNextSetResettingRepCount() {
        var controller = SetLifecycleController(restSeconds: 90)
        controller.arm()
        controller.repCompleted()
        controller.repCompleted()
        controller.autoRack()
        controller.restTick(elapsed: 0)
        controller.restTick(elapsed: 90)
        XCTAssertEqual(controller.state, .complete)

        controller.arm()
        XCTAssertEqual(controller.state, .armed)
        XCTAssertEqual(controller.repCount, 0)
    }

    func test_grindingSpotEventRaisesAlertStageWhileRepping() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .grinding, timestamp: 1.0, repIndex: 0, confidence: 0.6, reason: .concentricTempo))
        XCTAssertEqual(controller.alertStage, .grinding)
        XCTAssertEqual(controller.state, .repping)
    }

    func test_rackItSpotEventEscalatesAlertStageBeyondGrinding() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .grinding, timestamp: 1.0, repIndex: 0, confidence: 0.6, reason: .concentricTempo))
        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.5, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        XCTAssertEqual(controller.alertStage, .rackIt)
    }

    func test_resolvedSpotEventClearsAlertStageWithoutLosingRepCount() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .grinding, timestamp: 1.0, repIndex: 0, confidence: 0.6, reason: .concentricTempo))
        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.5, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        controller.handle(spotEvent: SpotEvent(kind: .resolved, timestamp: 2.0, repIndex: 0, confidence: 0.5, reason: .lockout))
        XCTAssertEqual(controller.alertStage, .none)
        XCTAssertEqual(controller.repCount, 1)
        XCTAssertEqual(controller.state, .repping)
    }

    func test_spotEventWhileIdleIsIgnored() {
        var controller = SetLifecycleController()
        controller.handle(spotEvent: SpotEvent(kind: .grinding, timestamp: 1.0, repIndex: 0, confidence: 0.6, reason: .concentricTempo))
        XCTAssertEqual(controller.alertStage, .none)
        XCTAssertEqual(controller.state, .idle)
    }

    func test_restTickWhileIdleOrArmedIsIgnored() {
        var controller = SetLifecycleController()
        controller.restTick(elapsed: 5)
        XCTAssertEqual(controller.state, .idle)

        controller.arm()
        controller.restTick(elapsed: 5)
        XCTAssertEqual(controller.state, .armed)
    }
}
