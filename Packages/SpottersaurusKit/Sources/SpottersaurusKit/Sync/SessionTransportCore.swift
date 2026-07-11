//
//  SessionTransportCore.swift
//  SpottersaurusKit
//
//  The pure "transport core" that sits ABOVE the `SessionTransport` port
//  (ADR 0002 / P2-4b): given an `OutboundMessage` + the caller's current
//  `reachable` flag + its own coalescer state, decides WHAT the P2-5 adapter
//  should actually do, as pure data (`TransportAction`) — no `WCSession`, no
//  async I/O, no timers. The adapter executes the returned action(s) and
//  reports outcomes back via `didDeliver`/`didFail` so the core can decide
//  any follow-up action (durable fallback, flushing a coalesced pending
//  tick). This reproduces the concrete send/coalesce/fallback behavior
//  implemented today by `WatchPlannedSessionStore` (Watch) and `WatchLink`
//  (iPhone), as one pure, macOS-testable state machine, ready for both
//  adapters to shrink onto in P2-5.
//

import Foundation

/// What a `SessionTransport` adapter must actually do in response to an
/// offer or an outcome report. `.none` means there is nothing to do right
/// now (e.g. a coalesced tick got stored behind an in-flight send, or a
/// command was dropped because the peer is unreachable) — the adapter
/// performs no `WCSession` call for that offer.
public enum TransportAction: Sendable, Equatable {
    /// Send `message` live now (`WCSession.sendMessageData`-class API on the
    /// real adapter). Used for a reachable `.liveMessage`/`.coalescedLive`
    /// send.
    case sendLiveMessage(OutboundMessage)
    /// Send `message` live now, expecting a reply
    /// (`WCSession.sendMessage(_:replyHandler:errorHandler:)`-class API).
    /// Used for a reachable `.reliableWithReply` send.
    case sendReliableWithReply(OutboundMessage)
    /// Hand `message` to the durable/queued mechanism
    /// (`updateApplicationContext`/`transferUserInfo`-class API). Used for
    /// `.durableQueued` sends, an unreachable `.liveMessage` (re-routed), and
    /// the fallback after a reachable `.liveMessage` send fails.
    case sendDurable(OutboundMessage)
    /// Nothing to do right now.
    case none
}

/// The result of `SessionTransportCore.offer(_:reachable:)`: the action the
/// adapter should perform, plus an outcome the core already knows
/// synchronously — without waiting for any real send to resolve. `outcome`
/// is non-`nil` only when the core can state the final
/// `SessionTransportSendOutcome` without the adapter doing any I/O (a
/// `.reliableWithReply` offered while unreachable simply fails: there is no
/// durable fallback for a command). For actions that require the adapter to
/// actually talk to `WCSession` (`.sendLiveMessage`, `.sendReliableWithReply`),
/// `outcome` is `nil` — the adapter performs the send and, for delivery
/// classes the core tracks follow-up state for (`.coalescedLive`,
/// `.liveMessage`), reports the result back via `didDeliver`/`didFail`.
public struct SessionTransportOffer: Sendable, Equatable {
    public var action: TransportAction
    public var outcome: SessionTransportSendOutcome?

    public init(action: TransportAction, outcome: SessionTransportSendOutcome? = nil) {
        self.action = action
        self.outcome = outcome
    }
}

/// Pure decision layer above the `SessionTransport` port (ADR 0002). Owns no
/// `WCSession`, no threads, no timers — just the routing rules for each
/// `DeliveryClass` plus the coalesce-to-latest in-flight/pending state for
/// `.coalescedLive` sends (delegated to `LiveTickCoalescer`, not
/// reimplemented). One instance is meant to live per logical outbound
/// coalesced stream (in practice, per adapter instance — there is only one
/// live-tick stream per app run).
public struct SessionTransportCore: Sendable {
    /// Coalesce-to-latest in-flight/pending gate (ADR 0001), reused verbatim
    /// from `LiveTickCoalescer`. That type's API is fixed to
    /// `LiveTickEnvelope` (the concrete tick payload), while this core
    /// operates one level up on already-encoded `OutboundMessage`s — so
    /// `coalescerGate` is offered as a throwaway placeholder purely to drive
    /// the coalescer's in-flight/pending state transitions, while
    /// `pendingCoalesced` below tracks the *actual* `OutboundMessage` to
    /// send once that gate opens. The two are always kept in lockstep:
    /// whenever `coalescer`'s `offer`/`completed`/`failed` reports "there is
    /// a pending value", `pendingCoalesced` is what that value actually is.
    private var coalescer = LiveTickCoalescer()
    private var pendingCoalesced: OutboundMessage?

    /// Inert placeholder passed to `LiveTickCoalescer` solely to drive its
    /// in-flight/pending gate — its field values are never read back.
    private static let coalescerGate = LiveTickEnvelope(
        repCount: 0,
        currentVelocityMS: 0,
        heartRateBPM: 0,
        elapsedSeconds: 0
    )

    public init() {}

    /// Offers `message` for sending given whether the peer is currently
    /// `reachable`, per `message.deliveryClass`:
    /// - `.liveMessage`: reachable -> send live; unreachable -> re-routed to
    ///   durable (matches `WatchLink`'s live-send-else-durable fallback).
    /// - `.reliableWithReply`: reachable -> send live-with-reply; unreachable
    ///   -> no action, immediate `.failed` outcome (a command cannot be
    ///   queued — the Watch can't be commanded while offline).
    /// - `.durableQueued`: always routed to durable, reachable or not (the
    ///   "opportunistic live-then-durable-on-failure" optimization some
    ///   adapters apply for this class today stays adapter-internal — see
    ///   this type's header and the `DeliveryClass.durableQueued` doc).
    /// - `.coalescedLive`: unreachable -> dropped, no action (best-effort,
    ///   matches today's `send(liveTick:)` reachability guard). Reachable ->
    ///   routed through the coalescer: idle -> send now, mark in-flight;
    ///   in-flight already -> stored as pending-latest, no action now.
    public mutating func offer(_ message: OutboundMessage, reachable: Bool) -> SessionTransportOffer {
        switch message.deliveryClass {
        case .liveMessage:
            return reachable
                ? SessionTransportOffer(action: .sendLiveMessage(message))
                : SessionTransportOffer(action: .sendDurable(message), outcome: .queued)

        case .reliableWithReply:
            return reachable
                ? SessionTransportOffer(action: .sendReliableWithReply(message))
                : SessionTransportOffer(action: .none, outcome: .failed)

        case .durableQueued:
            return SessionTransportOffer(action: .sendDurable(message), outcome: .queued)

        case .coalescedLive:
            guard reachable else {
                return SessionTransportOffer(action: .none)
            }

            if coalescer.offer(Self.coalescerGate) != nil {
                return SessionTransportOffer(action: .sendLiveMessage(message))
            }

            pendingCoalesced = message
            return SessionTransportOffer(action: .none)
        }
    }

    /// The adapter's send of `message` reached the peer. Only meaningful for
    /// `.coalescedLive` (the only class this core tracks in-flight state
    /// for): frees the coalescer's in-flight slot and, if a fresher tick
    /// arrived while this one was in flight, returns `.sendLiveMessage` for
    /// it so the adapter flushes it immediately — mirrors
    /// `WatchPlannedSessionStore.markLiveTickDelivered`. No-op for every
    /// other delivery class.
    public mutating func didDeliver(_ message: OutboundMessage) -> TransportAction {
        guard message.deliveryClass == .coalescedLive else { return .none }
        return flushCoalesced(coalescer.completed())
    }

    /// The adapter's send of `message` failed.
    /// - `.coalescedLive`: frees the coalescer's in-flight slot the same way
    ///   `didDeliver` does; if a pending-latest tick was waiting, returns
    ///   `.sendLiveMessage` for it. The adapter is expected to apply its own
    ///   small backoff before actually sending — this core has no wall-clock
    ///   concept, mirroring `LiveTickCoalescer.failed()`'s own doc.
    /// - `.liveMessage`: a reachable live attempt failed after being offered
    ///   — falls back to durable for the *same* message, matching
    ///   `WatchLink.sendLive`'s error path.
    /// - everything else: no-op (no fallback modeled for a failed
    ///   `.reliableWithReply`/`.durableQueued` send).
    public mutating func didFail(_ message: OutboundMessage) -> TransportAction {
        switch message.deliveryClass {
        case .coalescedLive:
            return flushCoalesced(coalescer.failed())

        case .liveMessage:
            return .sendDurable(message)

        case .reliableWithReply, .durableQueued:
            return .none
        }
    }

    /// Shared `didDeliver`/`didFail` tail: `gateResult` is whatever
    /// `LiveTickCoalescer.completed()`/`.failed()` returned (non-`nil` iff a
    /// pending-latest tick exists). When non-`nil`, `pendingCoalesced` holds
    /// the real `OutboundMessage` to send next (kept in lockstep with the
    /// coalescer — see `coalescer`'s doc comment).
    private mutating func flushCoalesced(_ gateResult: LiveTickEnvelope?) -> TransportAction {
        guard gateResult != nil, let next = pendingCoalesced else { return .none }
        pendingCoalesced = nil
        return .sendLiveMessage(next)
    }
}
