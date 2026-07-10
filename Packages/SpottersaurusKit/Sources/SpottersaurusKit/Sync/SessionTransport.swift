//
//  SessionTransport.swift
//  SpottersaurusKit
//
//  The hexagonal transport PORT (ADR 0002 / `docs/architecture.md` §3): a
//  platform-neutral protocol + supporting value types describing every
//  Watch <-> iPhone message this app sends, without ever importing
//  WatchConnectivity. Each app target ships a `WCSessionTransport` ADAPTER
//  (`Spottersaurus/App/WatchLink.swift`,
//  `Spottersaurus Watch App/App/WatchPlannedSessionStore.swift` today) that
//  will conform to `SessionTransport` and do the actual `WCSession` calls
//  (that adapter shrink is P2-5, not this task).
//
//  This file defines the SEAM ONLY — no send-decision logic (which
//  `DeliveryClass` to pick, live-vs-durable fallback ordering, retry/backoff)
//  lives here. That's the pure "transport core" that will sit *above* this
//  port (P2-4b) and the durable-queue policy that sits alongside it (P2-4c).
//

import Foundation

/// The delivery semantics an `OutboundMessage` needs from the transport,
/// distilled from the concrete `WCSession` send/receive matrix implemented
/// today by `WatchLink` (iPhone) and `WatchPlannedSessionStore` (Watch).
/// This describes *what guarantee the message needs*, not which `WCSession`
/// API fulfills it — that mapping is the adapter's job.
public enum DeliveryClass: String, Sendable, Equatable, CaseIterable, Codable {
    /// Requires the peer to be currently reachable; no reply payload is
    /// meaningful, only "did this reach the peer". Maps today to
    /// `WCSession.sendMessageData` on the live path of a planned-session
    /// send (`WatchLink.sendLive`). If the peer isn't reachable, the message
    /// isn't queued under this class — a fresh attempt is made under
    /// `.durableQueued` instead (that re-attempt sequencing is 4b's job, not
    /// this port's).
    case liveMessage

    /// Requires the peer to be currently reachable *and* expects a reply
    /// payload before the send is considered complete. Maps today to
    /// `WCSession.sendMessage(_:replyHandler:errorHandler:)`, used for the
    /// Watch command round-trip (`WatchLink.send(command:)`). Has no durable
    /// fallback: if the peer isn't reachable, the send simply fails (the
    /// Watch cannot be commanded while offline).
    case reliableWithReply

    /// A high-frequency outbound stream where only the freshest value ever
    /// matters and an in-flight send must never block or drop a fresher one.
    /// Maps today to the live tick, whose "coalesce to latest" policy is
    /// already owned by `LiveTickCoalescer` — this class exists so 4b's pure
    /// core knows to route sends through that coalescer rather than sending
    /// every offered message immediately.
    case coalescedLive

    /// Must survive the peer being unreachable — delivered via a
    /// durable/queued mechanism (`updateApplicationContext` /
    /// `transferUserInfo` on the real adapter), not a live message. Maps
    /// today to the finished session, the live-set lifecycle event, and the
    /// fallback attempt for a planned session whose live send failed or
    /// whose peer wasn't reachable.
    ///
    /// Note: today's adapters *also* opportunistically try a live
    /// `sendMessage` for the finished session and lifecycle event before
    /// falling back to a durable transfer when reachable — see this file's
    /// header comment / the 4a report for why that optimization doesn't need
    /// its own `DeliveryClass` case.
    case durableQueued
}

/// One outbound message: a `WireKeys` identifier, its already-encoded
/// payload, and the delivery guarantee it needs. This is the only thing a
/// `SessionTransport` conformance's `send(_:)` accepts — pairing the wire key
/// with the `DeliveryClass` here (rather than passing them as separate
/// parameters) is what lets 4b's send-decision logic stay a pure function
/// from "what do I need to send and how" to a sequence of `OutboundMessage`
/// values, with no `WCSession` in sight.
public struct OutboundMessage: Sendable, Equatable {
    /// One of the `WireKeys` constants identifying the payload's type on the
    /// wire (e.g. `WireKeys.plannedSession`).
    public var wireKey: String
    /// The already-`Codable`-encoded payload (a `SessionEnvelope`,
    /// `LiveTickEnvelope`, etc., encoded by the caller before this value is
    /// constructed — this port is encoding-agnostic).
    public var payload: Data
    /// The delivery guarantee this send needs from the adapter.
    public var deliveryClass: DeliveryClass

    public init(wireKey: String, payload: Data, deliveryClass: DeliveryClass) {
        self.wireKey = wireKey
        self.payload = payload
        self.deliveryClass = deliveryClass
    }
}

/// The result of attempting to send one `OutboundMessage`. Carries just
/// enough information for a pure decision layer (4b) to decide whether a
/// fallback attempt (e.g. re-sending the same payload as `.durableQueued`
/// after a `.liveMessage` attempt fails) is needed — no retry/backoff policy
/// lives on this type itself.
public enum SessionTransportSendOutcome: Sendable, Equatable {
    /// Reached the peer over the live wire. Carries the reply payload for
    /// `.reliableWithReply` sends (`nil` for delivery classes with no
    /// meaningful reply).
    case delivered(reply: Data?)
    /// Not sent live; handed to a durable/queued mechanism instead. The
    /// message will arrive once the peer is next reachable, not now.
    case queued
    /// Could not be delivered by any path (e.g. `WCSession` unsupported, or
    /// a `.reliableWithReply`/`.liveMessage` send with no durable fallback
    /// failed outright).
    case failed
}

/// One inbound message as decoded off the wire by a `SessionTransport`
/// adapter, keyed by which `WireKeys` constant it arrived under. Carries raw
/// `Data` only — decoding into the concrete envelope type (`SessionEnvelope`,
/// `LiveTickEnvelope`, ...) is the app/decoder layer's job, not this port's.
public enum InboundMessage: Sendable, Equatable {
    /// A `PlannedSessionEnvelope`, wire key `WireKeys.plannedSession`.
    case plannedSession(Data)
    /// A `WatchCommandEnvelope`, wire key `WireKeys.watchCommand`.
    case watchCommand(Data)
    /// A `LiveTickEnvelope`, wire key `WireKeys.liveTick`. (Today's live
    /// adapters exchange this bare, with no key wrapper, since
    /// `didReceiveMessageData` carries only one kind of payload — this case
    /// still records the intended key so the port's inbound vocabulary
    /// matches its outbound one.)
    case liveTick(Data)
    /// A `LiveSetLifecycleEnvelope`, wire key `WireKeys.liveSetLifecycle`.
    case lifecycle(Data)
    /// A `SessionEnvelope` (finished session), wire key
    /// `WireKeys.finishedSession`.
    case finishedSession(Data)

    /// The `WireKeys` constant this case travels under.
    public var wireKey: String {
        switch self {
        case .plannedSession: WireKeys.plannedSession
        case .watchCommand: WireKeys.watchCommand
        case .liveTick: WireKeys.liveTick
        case .lifecycle: WireKeys.liveSetLifecycle
        case .finishedSession: WireKeys.finishedSession
        }
    }

    /// The raw payload carried by this case, regardless of which one it is.
    public var payload: Data {
        switch self {
        case let .plannedSession(data),
             let .watchCommand(data),
             let .liveTick(data),
             let .lifecycle(data),
             let .finishedSession(data):
            data
        }
    }

    /// Builds the typed inbound case matching `wireKey`, or `nil` if the key
    /// isn't one of the wire contract's known keys — the defensive default
    /// for an adapter that received a payload under an unrecognized/future
    /// key.
    public init?(wireKey: String, payload: Data) {
        switch wireKey {
        case WireKeys.plannedSession: self = .plannedSession(payload)
        case WireKeys.watchCommand: self = .watchCommand(payload)
        case WireKeys.liveTick: self = .liveTick(payload)
        case WireKeys.liveSetLifecycle: self = .lifecycle(payload)
        case WireKeys.finishedSession: self = .finishedSession(payload)
        default: return nil
        }
    }
}

/// Receives every inbound message a `SessionTransport` adapter decodes off
/// the wire. Kept as its own protocol (rather than a bare closure property on
/// `SessionTransport`) so a conforming type can be a reference type that
/// hands the message to multiple internal handlers (mirroring how
/// `WatchLink` today fans a decoded payload out to `onLiveTick` /
/// `onFinishedSession` / `onLifecycle`), and so the fake transport below can
/// assert against a plain recorder.
public protocol SessionTransportInboundSink: Sendable {
    func transport(_ transport: any SessionTransport, didReceive message: InboundMessage) async
}

/// The platform-neutral transport port (ADR 0002). An adapter conforming to
/// this in an app target owns the real `WCSession` — Kit only ever sees this
/// protocol, so `Sync` logic built atop it (4b/4c) compiles and unit-tests on
/// macOS with no WatchConnectivity in sight.
///
/// Deliberately minimal for 4a: one send entry point, one way to observe
/// connection state, one way to register where inbound messages land. Which
/// `DeliveryClass` to send under, fallback ordering, coalescing, and durable-
/// queue flush timing are NOT decided here — those are 4b/4c, built as pure
/// logic that calls this protocol's `send(_:)`.
public protocol SessionTransport: Sendable {
    /// Current reachability/activation, already reduced to a single status
    /// (see `ConnectionStatus`). Declared `async` so an actor-isolated
    /// adapter can satisfy this requirement without exposing its isolation.
    var connectionStatus: ConnectionStatus { get async }

    /// Attempts to deliver `message` per its `deliveryClass`. The adapter
    /// alone decides which concrete `WCSession` API fulfills each
    /// `DeliveryClass` — this port does not prescribe it.
    @discardableResult
    func send(_ message: OutboundMessage) async -> SessionTransportSendOutcome

    /// Installs the sink that receives every inbound message this adapter
    /// decodes off the wire. There is at most one sink at a time; passing a
    /// new value replaces whatever was registered before, and `nil` clears
    /// it.
    func setInboundSink(_ sink: SessionTransportInboundSink?) async
}
