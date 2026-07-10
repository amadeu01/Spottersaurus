//
//  SessionTransportFakes.swift
//  SpottersaurusKitTests
//
//  Shared, headless test doubles for the `SessionTransport` port
//  (`Sync/SessionTransport.swift`). Lives in the test target (not
//  `Sources/`) since it's test scaffolding, not part of the shipped library —
//  but it's intentionally general enough that P2-4b/P2-4c can drive their
//  decision/queue logic against it too, without any WatchConnectivity or
//  device dependency.
//

import Foundation
@testable import SpottersaurusKit

/// Records every message `send(_:)` receives and lets tests stub the outcome
/// per `DeliveryClass`, proving `SessionTransport` is implementable headlessly
/// on macOS.
actor FakeSessionTransport: SessionTransport {
    private(set) var sentMessages: [OutboundMessage] = []
    private var stubbedOutcomes: [DeliveryClass: SessionTransportSendOutcome] = [:]
    private(set) var connectionStatus: ConnectionStatus
    private var sink: SessionTransportInboundSink?

    init(connectionStatus: ConnectionStatus = .connected) {
        self.connectionStatus = connectionStatus
    }

    /// Configures the outcome the next (and all subsequent) `send(_:)` calls
    /// for `deliveryClass` will return. Defaults to `.delivered(reply: nil)`
    /// when nothing is stubbed.
    func stub(outcome: SessionTransportSendOutcome, for deliveryClass: DeliveryClass) {
        stubbedOutcomes[deliveryClass] = outcome
    }

    func setConnectionStatus(_ status: ConnectionStatus) {
        connectionStatus = status
    }

    func send(_ message: OutboundMessage) async -> SessionTransportSendOutcome {
        sentMessages.append(message)
        return stubbedOutcomes[message.deliveryClass] ?? .delivered(reply: nil)
    }

    func setInboundSink(_ sink: SessionTransportInboundSink?) async {
        self.sink = sink
    }

    /// Test-only hook: delivers `message` straight to whatever sink is
    /// currently registered, as if it had just arrived off the wire.
    func deliverToSink(_ message: InboundMessage) async {
        await sink?.transport(self, didReceive: message)
    }
}

/// Plain recorder conforming to `SessionTransportInboundSink`, so tests can
/// assert on exactly what a transport handed to its sink.
actor RecordingInboundSink: SessionTransportInboundSink {
    private(set) var received: [InboundMessage] = []

    func transport(_ transport: any SessionTransport, didReceive message: InboundMessage) async {
        received.append(message)
    }
}
