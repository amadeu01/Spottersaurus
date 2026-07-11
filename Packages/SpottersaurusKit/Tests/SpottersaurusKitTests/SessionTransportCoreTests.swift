//
//  SessionTransportCoreTests.swift
//  SpottersaurusKitTests
//
//  TDD coverage for the P2-4b pure transport core: given an `OutboundMessage`
//  + reachability (+ its own coalescer state), `SessionTransportCore` must
//  emit exactly the `TransportAction` the concrete adapters
//  (`WatchPlannedSessionStore`, `WatchLink`) perform today for each
//  `DeliveryClass` — with no `WCSession`/I/O in sight.
//

import Foundation
import Testing
@testable import SpottersaurusKit

struct SessionTransportCoreTests {

    private func message(
        wireKey: String = WireKeys.liveTick,
        deliveryClass: DeliveryClass,
        byte: UInt8 = 0x1
    ) -> OutboundMessage {
        OutboundMessage(wireKey: wireKey, payload: Data([byte]), deliveryClass: deliveryClass)
    }

    // MARK: - .liveMessage

    @Test func liveMessageReachableSendsLive() {
        var core = SessionTransportCore()
        let msg = message(wireKey: WireKeys.plannedSession, deliveryClass: .liveMessage)

        let offer = core.offer(msg, reachable: true)

        #expect(offer.action == .sendLiveMessage(msg))
        #expect(offer.outcome == nil)
    }

    @Test func liveMessageUnreachableReRoutesToDurable() {
        var core = SessionTransportCore()
        let msg = message(wireKey: WireKeys.plannedSession, deliveryClass: .liveMessage)

        let offer = core.offer(msg, reachable: false)

        #expect(offer.action == .sendDurable(msg))
        #expect(offer.outcome == .queued)
    }

    @Test func liveMessageSendFailureWhileReachableFallsBackToDurable() {
        var core = SessionTransportCore()
        let msg = message(wireKey: WireKeys.plannedSession, deliveryClass: .liveMessage)
        _ = core.offer(msg, reachable: true)

        let followUp = core.didFail(msg)

        #expect(followUp == .sendDurable(msg))
    }

    @Test func liveMessageDeliverySuccessProducesNoFollowUp() {
        var core = SessionTransportCore()
        let msg = message(wireKey: WireKeys.plannedSession, deliveryClass: .liveMessage)
        _ = core.offer(msg, reachable: true)

        #expect(core.didDeliver(msg) == .none)
    }

    // MARK: - .reliableWithReply

    @Test func reliableWithReplyReachableSendsWithReply() {
        var core = SessionTransportCore()
        let msg = message(wireKey: WireKeys.watchCommand, deliveryClass: .reliableWithReply)

        let offer = core.offer(msg, reachable: true)

        #expect(offer.action == .sendReliableWithReply(msg))
        #expect(offer.outcome == nil)
    }

    @Test func reliableWithReplyUnreachableFailsWithNoAction() {
        var core = SessionTransportCore()
        let msg = message(wireKey: WireKeys.watchCommand, deliveryClass: .reliableWithReply)

        let offer = core.offer(msg, reachable: false)

        #expect(offer.action == .none)
        #expect(offer.outcome == .failed)
    }

    // MARK: - .durableQueued

    @Test func durableQueuedAlwaysSendsDurableRegardlessOfReachability() {
        var core = SessionTransportCore()
        let msg = message(wireKey: WireKeys.finishedSession, deliveryClass: .durableQueued)

        let reachableOffer = core.offer(msg, reachable: true)
        let unreachableOffer = core.offer(msg, reachable: false)

        #expect(reachableOffer.action == .sendDurable(msg))
        #expect(reachableOffer.outcome == .queued)
        #expect(unreachableOffer.action == .sendDurable(msg))
        #expect(unreachableOffer.outcome == .queued)
    }

    // MARK: - .coalescedLive

    @Test func coalescedLiveIdleReachableSendsAndGoesInFlight() {
        var core = SessionTransportCore()
        let tick = message(deliveryClass: .coalescedLive, byte: 1)

        let offer = core.offer(tick, reachable: true)

        #expect(offer.action == .sendLiveMessage(tick))
        #expect(offer.outcome == nil)
    }

    @Test func coalescedLiveUnreachableDropsWithNoAction() {
        var core = SessionTransportCore()
        let tick = message(deliveryClass: .coalescedLive, byte: 1)

        let offer = core.offer(tick, reachable: false)

        #expect(offer.action == .none)
        #expect(offer.outcome == nil)
    }

    @Test func coalescedLiveSecondOfferWhileInFlightIsStoredAsPendingNoAction() {
        var core = SessionTransportCore()
        let first = message(deliveryClass: .coalescedLive, byte: 1)
        let second = message(deliveryClass: .coalescedLive, byte: 2)
        _ = core.offer(first, reachable: true) // now in flight

        let offer = core.offer(second, reachable: true)

        #expect(offer.action == .none)
    }

    @Test func coalescedLiveOnlyFreshestPendingSurvivesMultipleOffersWhileInFlight() {
        var core = SessionTransportCore()
        let first = message(deliveryClass: .coalescedLive, byte: 1)
        _ = core.offer(first, reachable: true) // in flight

        _ = core.offer(message(deliveryClass: .coalescedLive, byte: 2), reachable: true)
        _ = core.offer(message(deliveryClass: .coalescedLive, byte: 3), reachable: true)
        let fourth = message(deliveryClass: .coalescedLive, byte: 4)
        _ = core.offer(fourth, reachable: true)

        let flushed = core.didDeliver(first)

        #expect(flushed == .sendLiveMessage(fourth))
    }

    @Test func coalescedLiveDidDeliverWithNoPendingReturnsNoneAndGoesIdle() {
        var core = SessionTransportCore()
        let first = message(deliveryClass: .coalescedLive, byte: 1)
        _ = core.offer(first, reachable: true)

        #expect(core.didDeliver(first) == .none)

        // Idle again: a fresh offer should send immediately, not coalesce.
        let second = message(deliveryClass: .coalescedLive, byte: 2)
        #expect(core.offer(second, reachable: true).action == .sendLiveMessage(second))
    }

    @Test func coalescedLiveDidDeliverFlushesPendingLatest() {
        var core = SessionTransportCore()
        let first = message(deliveryClass: .coalescedLive, byte: 1)
        let second = message(deliveryClass: .coalescedLive, byte: 2)
        _ = core.offer(first, reachable: true) // in flight
        _ = core.offer(second, reachable: true) // pending

        let flushed = core.didDeliver(first)

        #expect(flushed == .sendLiveMessage(second))
    }

    @Test func coalescedLiveDidFailWithNoPendingReturnsNone() {
        var core = SessionTransportCore()
        let first = message(deliveryClass: .coalescedLive, byte: 1)
        _ = core.offer(first, reachable: true)

        #expect(core.didFail(first) == .none)
    }

    @Test func coalescedLiveDidFailRetriesPendingLatest() {
        var core = SessionTransportCore()
        let first = message(deliveryClass: .coalescedLive, byte: 1)
        let second = message(deliveryClass: .coalescedLive, byte: 2)
        _ = core.offer(first, reachable: true) // in flight
        _ = core.offer(second, reachable: true) // pending

        let retry = core.didFail(first)

        #expect(retry == .sendLiveMessage(second))
    }

    @Test func coalescedLiveAfterFlushReenteringInFlightCoalescesAgain() {
        var core = SessionTransportCore()
        let first = message(deliveryClass: .coalescedLive, byte: 1)
        let second = message(deliveryClass: .coalescedLive, byte: 2)
        _ = core.offer(first, reachable: true) // in flight
        _ = core.offer(second, reachable: true) // pending
        _ = core.didDeliver(first) // flushes second, re-enters in-flight with `second`

        let third = message(deliveryClass: .coalescedLive, byte: 3)
        let offer = core.offer(third, reachable: true)

        #expect(offer.action == .none)

        let flushed = core.didDeliver(second)
        #expect(flushed == .sendLiveMessage(third))
    }
}
