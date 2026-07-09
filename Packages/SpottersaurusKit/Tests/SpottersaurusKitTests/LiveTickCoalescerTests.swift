//
//  LiveTickCoalescerTests.swift
//  SpottersaurusKitTests
//
//  TDD coverage for `LiveTickCoalescer` (ADR 0001 "coalesce-to-latest"): the
//  Watch -> iPhone live-tick transport must never drop the freshest tick
//  while a send is in flight, and must send exactly the latest one once the
//  in-flight send completes.
//

import XCTest
@testable import SpottersaurusKit

final class LiveTickCoalescerTests: XCTestCase {

    private func makeTick(repCount: Int, velocity: Double = 0.4) -> LiveTickEnvelope {
        LiveTickEnvelope(
            repCount: repCount,
            currentVelocityMS: velocity,
            heartRateBPM: 120,
            elapsedSeconds: Double(repCount) * 2
        )
    }

    func testOfferWhenIdleReturnsTickAndGoesInFlight() {
        var coalescer = LiveTickCoalescer()
        let tick = makeTick(repCount: 1)

        let sent = coalescer.offer(tick)

        XCTAssertEqual(sent, tick)
    }

    func testOffersWhileInFlightAllReturnNilAndOnlyLastIsRetained() {
        var coalescer = LiveTickCoalescer()
        _ = coalescer.offer(makeTick(repCount: 1)) // now in flight

        let second = coalescer.offer(makeTick(repCount: 2))
        let third = coalescer.offer(makeTick(repCount: 3))
        let fourth = coalescer.offer(makeTick(repCount: 4))

        XCTAssertNil(second)
        XCTAssertNil(third)
        XCTAssertNil(fourth)

        // Only the freshest (repCount 4) should come back out.
        let next = coalescer.completed()
        XCTAssertEqual(next?.repCount, 4)
    }

    func testCompletedReturnsRetainedLatestAndReentersInFlight() {
        var coalescer = LiveTickCoalescer()
        _ = coalescer.offer(makeTick(repCount: 1))
        _ = coalescer.offer(makeTick(repCount: 2)) // pending, in flight already

        let next = coalescer.completed()
        XCTAssertEqual(next?.repCount, 2)

        // Having re-entered in-flight, a fresh offer must coalesce again
        // rather than send immediately.
        let offeredWhileStillInFlight = coalescer.offer(makeTick(repCount: 3))
        XCTAssertNil(offeredWhileStillInFlight)
    }

    func testCompletedWithNothingPendingReturnsNilAndGoesIdle() {
        var coalescer = LiveTickCoalescer()
        _ = coalescer.offer(makeTick(repCount: 1))

        let next = coalescer.completed()
        XCTAssertNil(next)

        // Idle again: a fresh offer should send immediately.
        let sent = coalescer.offer(makeTick(repCount: 2))
        XCTAssertEqual(sent?.repCount, 2)
    }

    func testFreshOfferAfterIdleSendsImmediatelyFreshestValueNeverLost() {
        var coalescer = LiveTickCoalescer()
        _ = coalescer.offer(makeTick(repCount: 1))
        XCTAssertNil(coalescer.completed()) // back to idle

        let sent = coalescer.offer(makeTick(repCount: 2, velocity: 0.55))
        XCTAssertEqual(sent?.repCount, 2)
        XCTAssertEqual(sent?.currentVelocityMS, 0.55)
    }

    func testFailedFreesInFlightSlotAndReturnsPendingLikeCompleted() {
        var coalescer = LiveTickCoalescer()
        _ = coalescer.offer(makeTick(repCount: 1))
        _ = coalescer.offer(makeTick(repCount: 2)) // pending

        let next = coalescer.failed()
        XCTAssertEqual(next?.repCount, 2)
    }

    func testFailedWithNothingPendingReturnsNilAndGoesIdle() {
        var coalescer = LiveTickCoalescer()
        _ = coalescer.offer(makeTick(repCount: 1))

        XCTAssertNil(coalescer.failed())

        let sent = coalescer.offer(makeTick(repCount: 2))
        XCTAssertEqual(sent?.repCount, 2)
    }
}
