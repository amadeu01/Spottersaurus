//
//  SessionTransportTests.swift
//  SpottersaurusKitTests
//
//  TDD coverage for the P2-4a `SessionTransport` port seam: `DeliveryClass`,
//  `OutboundMessage`, `InboundMessage`, and that the protocol itself is
//  implementable headlessly (via `FakeSessionTransport`) with no
//  WatchConnectivity in sight. No send-decision logic is under test here —
//  that lands with the pure transport core in P2-4b.
//

import Foundation
import Testing
@testable import SpottersaurusKit

struct SessionTransportTests {

    // MARK: - DeliveryClass

    @Test func deliveryClassHasExactlyTheFourMatrixCases() {
        #expect(Set(DeliveryClass.allCases) == [.liveMessage, .reliableWithReply, .coalescedLive, .durableQueued])
    }

    // MARK: - OutboundMessage

    @Test func outboundMessageConstructsForEachDeliveryClass() {
        let payload = Data([0x01, 0x02, 0x03])

        let planned = OutboundMessage(wireKey: WireKeys.plannedSession, payload: payload, deliveryClass: .liveMessage)
        let command = OutboundMessage(wireKey: WireKeys.watchCommand, payload: payload, deliveryClass: .reliableWithReply)
        let tick = OutboundMessage(wireKey: WireKeys.liveTick, payload: payload, deliveryClass: .coalescedLive)
        let finished = OutboundMessage(wireKey: WireKeys.finishedSession, payload: payload, deliveryClass: .durableQueued)

        #expect(planned.deliveryClass == .liveMessage)
        #expect(command.deliveryClass == .reliableWithReply)
        #expect(tick.deliveryClass == .coalescedLive)
        #expect(finished.deliveryClass == .durableQueued)
        #expect(planned.wireKey == WireKeys.plannedSession)
        #expect(planned.payload == payload)
    }

    @Test func outboundMessageEquatableComparesAllFields() {
        let a = OutboundMessage(wireKey: WireKeys.liveTick, payload: Data([1]), deliveryClass: .coalescedLive)
        let b = OutboundMessage(wireKey: WireKeys.liveTick, payload: Data([1]), deliveryClass: .coalescedLive)
        let differentPayload = OutboundMessage(wireKey: WireKeys.liveTick, payload: Data([2]), deliveryClass: .coalescedLive)

        #expect(a == b)
        #expect(a != differentPayload)
    }

    // MARK: - InboundMessage

    @Test func inboundMessageWireKeyRoundTripsForEveryCase() {
        let payload = Data([0xAA])
        let cases: [(String, InboundMessage)] = [
            (WireKeys.plannedSession, .plannedSession(payload)),
            (WireKeys.watchCommand, .watchCommand(payload)),
            (WireKeys.liveTick, .liveTick(payload)),
            (WireKeys.liveSetLifecycle, .lifecycle(payload)),
            (WireKeys.finishedSession, .finishedSession(payload)),
        ]

        for (key, expected) in cases {
            #expect(InboundMessage(wireKey: key, payload: payload) == expected)
            #expect(expected.wireKey == key)
            #expect(expected.payload == payload)
        }
    }

    @Test func inboundMessageInitReturnsNilForUnknownWireKey() {
        #expect(InboundMessage(wireKey: "somethingUnrecognized", payload: Data()) == nil)
    }

    // MARK: - FakeSessionTransport (protocol implementable headlessly)

    @Test func fakeTransportRecordsSentMessagesAndReturnsStubbedOutcome() async {
        let transport = FakeSessionTransport()
        let message = OutboundMessage(wireKey: WireKeys.finishedSession, payload: Data([0x9]), deliveryClass: .durableQueued)
        await transport.stub(outcome: .queued, for: .durableQueued)

        let outcome = await transport.send(message)

        #expect(outcome == .queued)
        let sent = await transport.sentMessages
        #expect(sent == [message])
    }

    @Test func fakeTransportDefaultsToDeliveredWhenNothingStubbed() async {
        let transport = FakeSessionTransport()
        let message = OutboundMessage(wireKey: WireKeys.watchCommand, payload: Data(), deliveryClass: .reliableWithReply)

        let outcome = await transport.send(message)

        #expect(outcome == .delivered(reply: nil))
    }

    @Test func fakeTransportExposesConnectionStatus() async {
        let transport = FakeSessionTransport(connectionStatus: .pairedNotReachable)

        #expect(await transport.connectionStatus == .pairedNotReachable)

        await transport.setConnectionStatus(.connected)
        #expect(await transport.connectionStatus == .connected)
    }

    @Test func fakeTransportDeliversInboundMessagesToRegisteredSink() async {
        let transport = FakeSessionTransport()
        let sink = RecordingInboundSink()
        await transport.setInboundSink(sink)

        await transport.deliverToSink(.liveTick(Data([0x1])))

        let received = await sink.received
        #expect(received == [.liveTick(Data([0x1]))])
    }

    @Test func fakeTransportReplacingSinkStopsDeliveryToThePreviousOne() async {
        let transport = FakeSessionTransport()
        let firstSink = RecordingInboundSink()
        let secondSink = RecordingInboundSink()
        await transport.setInboundSink(firstSink)
        await transport.setInboundSink(secondSink)

        await transport.deliverToSink(.finishedSession(Data([0x2])))

        let firstReceived = await firstSink.received
        let secondReceived = await secondSink.received
        #expect(firstReceived.isEmpty)
        #expect(secondReceived == [.finishedSession(Data([0x2]))])
    }
}
