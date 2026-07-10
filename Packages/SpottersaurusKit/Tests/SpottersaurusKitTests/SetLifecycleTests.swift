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

    func test_armFromIdleTransitionsToSettling() {
        // ADR 0006: Start begins the unrack/walkout/brace setup phase, not
        // rep counting — arm() now lands in .settling, not .repping.
        var controller = SetLifecycleController()
        controller.arm()
        XCTAssertEqual(controller.state, .settling)
    }

    func test_settlingWithNoRepStaysSettlingWithZeroReps() {
        // A stray motion sample or two during unrack/walkout must not
        // advance repCount or leave .settling on its own — only a genuine
        // (segmenter-gated) repCompleted() call does that.
        var controller = SetLifecycleController()
        controller.arm()
        XCTAssertEqual(controller.state, .settling)
        XCTAssertEqual(controller.repCount, 0)
    }

    func test_repCompletedWhileSettlingTransitionsToRepping_andIncrementsCount() {
        // The segmenter's gated first rep (P15-D2) is what ends .settling —
        // it counts as rep 1, not a zeroth "warmup" rep.
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
        XCTAssertEqual(controller.state, .settling)
    }

    func test_autoRackWhileReppingClearsAlertStage() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.0, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        XCTAssertEqual(controller.alertStage, .rackIt)

        controller.autoRack()
        XCTAssertEqual(controller.state, .racked)
        XCTAssertEqual(controller.alertStage, .none)
    }

    func test_autoRackWhileNotReppingDoesNotClearAlertStage() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.0, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        controller.autoRack()
        XCTAssertEqual(controller.state, .racked)
        // The first autoRack() call above did the (state == .repping)-gated
        // transition + clear. From here on we're already .racked with
        // alertStage already .none.
        XCTAssertEqual(controller.alertStage, .none)

        // Calling autoRack() again from .racked (not .repping) must be a
        // genuine no-op: the guard blocks it before either the state
        // transition or the alertStage reset run, so nothing changes.
        controller.autoRack()
        XCTAssertEqual(controller.state, .racked)
        XCTAssertEqual(controller.alertStage, .none)
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
        XCTAssertEqual(controller.state, .settling)
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

    func test_resolvedSpotEventClearsAlertStageWhileRacked() {
        var controller = SetLifecycleController()
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.0, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        controller.autoRack()
        XCTAssertEqual(controller.state, .racked)
        // autoRack() itself already clears alertStage (P1-1b belt-and-suspenders);
        // .resolved arriving afterwards must still be a harmless no-op.
        XCTAssertEqual(controller.alertStage, .none)

        controller.handle(spotEvent: SpotEvent(kind: .resolved, timestamp: 2.0, repIndex: 0, confidence: 0.5, reason: .lockout))
        XCTAssertEqual(controller.alertStage, .none)
        XCTAssertEqual(controller.state, .racked)
    }

    func test_resolvedSpotEventClearsAlertStageWhileResting() {
        var controller = SetLifecycleController(restSeconds: 90)
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.0, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        controller.autoRack()
        controller.restTick(elapsed: 0)
        XCTAssertEqual(controller.state, .resting)
        // autoRack() already cleared alertStage on the way here (P1-1b).
        XCTAssertEqual(controller.alertStage, .none)

        controller.handle(spotEvent: SpotEvent(kind: .resolved, timestamp: 2.0, repIndex: 0, confidence: 0.5, reason: .lockout))
        XCTAssertEqual(controller.alertStage, .none)
        XCTAssertEqual(controller.state, .resting)
    }

    func test_resolvedSpotEventClearsAlertStageWhileComplete() {
        var controller = SetLifecycleController(restSeconds: 90)
        controller.arm()
        controller.repCompleted()
        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.0, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        controller.autoRack()
        controller.restTick(elapsed: 0)
        controller.restTick(elapsed: 90)
        XCTAssertEqual(controller.state, .complete)
        // autoRack() already cleared alertStage on the way here (P1-1b).
        XCTAssertEqual(controller.alertStage, .none)

        controller.handle(spotEvent: SpotEvent(kind: .resolved, timestamp: 91.0, repIndex: 0, confidence: 0.5, reason: .lockout))
        XCTAssertEqual(controller.alertStage, .none)
        XCTAssertEqual(controller.state, .complete)
    }

    func test_grindingAndRackItSpotEventsStillIgnoredOutsideRepping() {
        var controller = SetLifecycleController(restSeconds: 90)
        controller.arm()
        controller.repCompleted()
        controller.autoRack()
        XCTAssertEqual(controller.state, .racked)

        controller.handle(spotEvent: SpotEvent(kind: .grinding, timestamp: 1.0, repIndex: 0, confidence: 0.6, reason: .concentricTempo))
        XCTAssertEqual(controller.alertStage, .none)

        controller.handle(spotEvent: SpotEvent(kind: .rackIt, timestamp: 1.5, repIndex: 0, confidence: 0.95, reason: .sustainedPin))
        XCTAssertEqual(controller.alertStage, .none)
    }

    func test_spotEventWhileIdleIsIgnored() {
        var controller = SetLifecycleController()
        controller.handle(spotEvent: SpotEvent(kind: .grinding, timestamp: 1.0, repIndex: 0, confidence: 0.6, reason: .concentricTempo))
        XCTAssertEqual(controller.alertStage, .none)
        XCTAssertEqual(controller.state, .idle)
    }

    func test_restTickWhileIdleOrSettlingIsIgnored() {
        var controller = SetLifecycleController()
        controller.restTick(elapsed: 5)
        XCTAssertEqual(controller.state, .idle)

        controller.arm()
        controller.restTick(elapsed: 5)
        XCTAssertEqual(controller.state, .settling)
    }
}
