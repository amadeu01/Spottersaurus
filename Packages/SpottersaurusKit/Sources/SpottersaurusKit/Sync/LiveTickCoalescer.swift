import Foundation

/// Pure "at most one send in flight, never drop the freshest tick" state
/// machine for the Watch -> iPhone `LiveTickEnvelope` transport (ADR 0001,
/// "coalesce-to-latest"). This replaces the old drop-on-in-flight behavior in
/// `WatchPlannedSessionStore.send(liveTick:)`, which silently discarded any
/// tick that arrived while a `sendMessageData` call was already outstanding —
/// including a rep-completion tick carrying a fresh Mean Concentric Velocity.
///
/// This type carries no transport/lock/timing logic of its own: the caller
/// (`WatchPlannedSessionStore`) owns the `WCSession` call, its own `NSLock`,
/// and any backoff timing. `LiveTickCoalescer` only tracks two things: are we
/// currently sending, and if so, what's the freshest tick waiting behind it.
public struct LiveTickCoalescer: Sendable {
    private var isInFlight = false
    private var pending: LiveTickEnvelope?

    public init() {}

    /// Offer a tick for sending.
    ///
    /// - If idle, marks in-flight and returns `tick` — the caller should send
    ///   it now.
    /// - If a send is already in flight, stores `tick` as the pending-latest
    ///   (overwriting any earlier pending tick) and returns `nil` — the
    ///   caller sends nothing now; the freshest tick will go out via
    ///   `completed()` once the in-flight send finishes.
    public mutating func offer(_ tick: LiveTickEnvelope) -> LiveTickEnvelope? {
        guard !isInFlight else {
            pending = tick
            return nil
        }

        isInFlight = true
        return tick
    }

    /// The in-flight send finished successfully. Marks idle; if a
    /// pending-latest tick was held, immediately re-enters in-flight and
    /// returns it (clearing pending) so the caller can send it right away.
    /// Returns `nil` when nothing was pending.
    public mutating func completed() -> LiveTickEnvelope? {
        isInFlight = false
        guard let next = pending else { return nil }

        pending = nil
        isInFlight = true
        return next
    }

    /// The in-flight send failed. Frees the in-flight slot the same way
    /// `completed()` does (including handing back any pending-latest tick to
    /// retry immediately), but the caller is expected to apply its own
    /// small/adaptive backoff before actually sending again — this type has
    /// no wall-clock/timing concept of its own.
    public mutating func failed() -> LiveTickEnvelope? {
        completed()
    }
}
