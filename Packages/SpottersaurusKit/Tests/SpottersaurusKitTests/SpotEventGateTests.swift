//
//  SpotEventGateTests.swift
//  SpottersaurusKitTests
//
//  Headless tests for the P1-1c "stuck RACK IT" fix: `SpotEngine.process`
//  re-emits every event still inside the rolling buffer on every tick, so the
//  caller must dedup before handing events to `SetLifecycleController`. These
//  tests prove `SpotEventGate` does that: same event admitted once, distinct
//  events (different repIndex or kind) always admitted, and replayed buffers
//  never re-yield already-seen events.
//

import XCTest
@testable import SpottersaurusKit

final class SpotEventGateTests: XCTestCase {

    private func event(
        kind: SpotEventKind,
        repIndex: Int,
        timestamp: TimeInterval = 0,
        confidence: Double = 0.9,
        reason: SpotReason = .sustainedPin
    ) -> SpotEvent {
        SpotEvent(kind: kind, timestamp: timestamp, repIndex: repIndex, confidence: confidence, reason: reason)
    }

    func test_firstOfferOfAnEventAdmitsIt() {
        var gate = SpotEventGate()
        let e = event(kind: .rackIt, repIndex: 0)
        XCTAssertEqual(gate.admitNew(from: [e]), [e])
    }

    func test_sameEventOfferedTwiceIsAdmittedOnlyOnce() {
        var gate = SpotEventGate()
        let e = event(kind: .rackIt, repIndex: 0)
        _ = gate.admitNew(from: [e])
        XCTAssertEqual(gate.admitNew(from: [e]), [])
    }

    func test_replayedFullBufferOnEveryTickDoesNotReYieldTheSameRackIt() {
        // Mirrors the real bug: `analysis.events` is the whole rolling window,
        // so the same rackIt for rep 0 shows up in every subsequent tick's
        // array even after the lifter has resolved it.
        var gate = SpotEventGate()
        let grinding = event(kind: .grinding, repIndex: 0, reason: .concentricTempo)
        let rackIt = event(kind: .rackIt, repIndex: 0, reason: .sustainedPin)

        let firstTick = gate.admitNew(from: [grinding, rackIt])
        XCTAssertEqual(firstTick, [grinding, rackIt])

        // Next three ticks replay the identical buffer (rep still in window).
        for _ in 0..<3 {
            XCTAssertEqual(gate.admitNew(from: [grinding, rackIt]), [])
        }
    }

    func test_resolvedEventAfterRackItIsStillAdmitted_differentKindSameRep() {
        var gate = SpotEventGate()
        let rackIt = event(kind: .rackIt, repIndex: 0)
        let resolved = event(kind: .resolved, repIndex: 0, reason: .lockout)

        _ = gate.admitNew(from: [rackIt])
        XCTAssertEqual(gate.admitNew(from: [rackIt, resolved]), [resolved])
    }

    func test_newRepIndexWithSameKindIsAdmitted_realNewGrindStillAlerts() {
        var gate = SpotEventGate()
        let repZeroRackIt = event(kind: .rackIt, repIndex: 0)
        let repOneRackIt = event(kind: .rackIt, repIndex: 1)

        _ = gate.admitNew(from: [repZeroRackIt])
        XCTAssertEqual(gate.admitNew(from: [repZeroRackIt, repOneRackIt]), [repOneRackIt])
    }

    func test_admitsOnlyTheNewSubsetPreservingOrder_whenMixedWithAlreadySeenEvents() {
        var gate = SpotEventGate()
        let a = event(kind: .grinding, repIndex: 0)
        let b = event(kind: .rackIt, repIndex: 0)
        let c = event(kind: .grinding, repIndex: 1)

        _ = gate.admitNew(from: [a])
        XCTAssertEqual(gate.admitNew(from: [a, b, c]), [b, c])
    }

    func test_emptyEventsYieldsEmptyAdmitted() {
        var gate = SpotEventGate()
        XCTAssertEqual(gate.admitNew(from: []), [])
    }

    func test_resetClearsSeenHistory_soANewSetsRepZeroIsNotPermanentlySilenced() {
        var gate = SpotEventGate()
        let repZeroGrinding = event(kind: .grinding, repIndex: 0)

        _ = gate.admitNew(from: [repZeroGrinding])
        XCTAssertEqual(gate.admitNew(from: [repZeroGrinding]), [], "sanity: already seen before reset")

        gate.reset()
        XCTAssertEqual(gate.admitNew(from: [repZeroGrinding]), [repZeroGrinding], "new set's rep 0 must re-alert after reset")
    }
}
