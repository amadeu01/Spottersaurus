import Foundation
import Observation
import WatchConnectivity
import SpottersaurusKit

@Observable
final class WatchPlannedSessionStore: NSObject, WCSessionDelegate {
    static let shared = WatchPlannedSessionStore()

    private let payloadKey = "plannedSession"
    private let liveTickKey = "liveTick"
    private let commandKey = "watchCommand"
    private let finishedSessionKey = "finishedSession"
    private let lifecycleKey = "liveSetLifecycle"
    private let defaultsKey = "Spottersaurus.lastPlannedSession"
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var plannedSession: PlannedSessionEnvelope?
    private var session: WCSession?
    /// Coalesce-to-latest state for the live-tick transport (ADR 0001):
    /// never drop the freshest tick behind an in-flight `sendMessageData`
    /// call — see `LiveTickCoalescer` (SpottersaurusKit/Sync). Guarded by
    /// `lock` alongside the rest of this class's mutable state.
    private var liveTickCoalescer = LiveTickCoalescer()
    /// Small, fixed backoff before retrying a live tick after a transport
    /// failure (ADR 0001: "no long hard failure-backoff", replacing the old
    /// 5 s hard-coded delay). This only delays the automatic retry of the
    /// tick the coalescer already promoted to pending — it never blocks a
    /// fresh `send(liveTick:)` call, which always coalesces through
    /// `liveTickCoalescer` normally.
    private let liveTickRetryBackoff: TimeInterval = 0.75
    private let logger = LoggerGroup.watch

    /// Latest `WCSession` state observed on the Watch side, pushed from
    /// `activationDidCompleteWith` and `sessionReachabilityDidChange`.
    /// watchOS's `WCSession` doesn't expose `isPaired`/`isWatchAppInstalled`
    /// (those are iOS-only APIs) — the Watch app only ever exists on the one
    /// Watch it's running on, paired to the one phone it's provisioned with,
    /// so both are true by construction whenever the session has activated.
    /// Reachability + activation state are the only two flags the Watch can
    /// actually observe, so `connectionStatus` feeds
    /// `ConnectionStatus.resolve(isPaired: true, isWatchAppInstalled: true,
    /// ...)` and lets the shared reducer collapse pre-activation to
    /// `.inactive`, activated-but-unreachable to `.pairedNotReachable`, and
    /// activated-and-reachable to `.connected`.
    private(set) var isReachable = false
    private(set) var activationState = 0

    /// Pure cursor over the most recently received `PlannedSessionEnvelope`'s
    /// ordered sets (`PlannedSessionCursor`, SpottersaurusKit). This is the
    /// M1b fix for the "everything is bench" bug: `currentPlannedSet()` used
    /// to read only `firstSet` and fall back to a hardcoded bench @ 100 kg
    /// when nothing had been received. `nil` means "no planned session has
    /// ever arrived" — the honest empty state `WatchRootView` renders
    /// instead of a fabricated set. Once a session lands, advancing past its
    /// last set makes `cursor.isFinished` true (session complete) — still
    /// not `nil`. `@Observable` via this class so `WatchRootView` re-renders
    /// reactively as sets progress, mirroring `isReachable`/`activationState`
    /// above.
    private(set) var cursor: PlannedSessionCursor?

    /// Pure projection of the flags above via the shared `ConnectionStatus`
    /// reducer (see the doc comment on `isReachable` for the watchOS
    /// isPaired/isWatchAppInstalled assumption).
    var connectionStatus: ConnectionStatus {
        ConnectionStatus.resolve(
            isPaired: true,
            isWatchAppInstalled: true,
            isReachable: isReachable,
            activationState: activationState
        )
    }

    override private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let envelope = try? decoder.decode(PlannedSessionEnvelope.self, from: data) {
            self.plannedSession = envelope
            self.cursor = PlannedSessionCursor(session: envelope)
        }

        if WCSession.isSupported() {
            self.session = WCSession.default
        }

        super.init()
        session?.delegate = self
        session?.activate()
        logger.info(.watchLink, "activated Watch WCSession supported=\(session != nil)")
        if let data = session?.applicationContext[payloadKey] as? Data {
            store(data)
        }
    }

    /// The set currently up in the Live Session, or `nil` when no planned
    /// session has ever been received — no bench/weight fallback (see
    /// `cursor`'s doc comment). `WatchRootView` renders an honest empty state
    /// on `nil` instead of fabricating a set.
    func currentPlannedSet() -> PlannedSetEnvelope? {
        cursor?.current
    }

    /// Advances the cursor to the next set once the current one has been
    /// racked and its rest has fully elapsed — see `WatchRootView`'s
    /// `onSetSessionComplete`. This only moves which prescription is "up
    /// next"; it never arms/starts anything (manual re-arm is still
    /// required, per M1b's safety posture). Safe to call repeatedly past the
    /// last set — the cursor itself clamps at `setCount`.
    func advanceCursor() {
        guard var advanced = cursor else { return }
        advanced.advance()
        cursor = advanced
        logger.notice(.watchLink, "advanced planned session cursor to setIndex=\(advanced.setIndex) of \(advanced.setCount)")
    }

    /// Coalesce-to-latest live-tick send (ADR 0001 / L2): never drops the
    /// freshest tick behind an in-flight `sendMessageData` call. `offer`
    /// either hands back this exact tick to send now (idle) or stores it as
    /// the pending-latest and returns `nil` (a send is already in flight) —
    /// in the latter case the completion/error handlers below flush it as
    /// soon as the in-flight send finishes.
    func send(liveTick: LiveTickEnvelope) {
        guard let session, session.isReachable else {
            logger.debug(.watchLink, "skipping live tick; phone not reachable")
            return
        }

        lock.lock()
        let toSendNow = liveTickCoalescer.offer(liveTick)
        lock.unlock()

        guard let toSendNow else {
            logger.debug(.watchLink, "coalescing live tick reps=\(liveTick.repCount); send already in flight")
            return
        }

        transmit(toSendNow, through: session)
    }

    /// Actually performs the `WCSession` round-trip for a tick the coalescer
    /// has already promoted to "in flight". Also used to flush a
    /// pending-latest tick once the previous send completes/fails/retries.
    private func transmit(_ tick: LiveTickEnvelope, through session: WCSession) {
        guard let data = try? encoder.encode(tick) else {
            logger.error(.watchLink, "live tick encode failed; freeing in-flight slot")
            freeLiveTickSlotAndFlushPending(through: session)
            return
        }

        logger.debug(.watchLink, "sending live tick reps=\(tick.repCount) velocity=\(tick.currentVelocityMS) hr=\(tick.heartRateBPM)")
        session.sendMessageData(data) { [weak self] _ in
            self?.markLiveTickDelivered(through: session)
        } errorHandler: { [weak self] error in
            self?.markLiveTickFailed(error, through: session)
        }
    }

    /// Emits a Live Set Lifecycle Event (`armed`/`ended` — ADR 0001 +
    /// `LiveSetLifecycleEnvelope`) to the iPhone as a KEYED message/userInfo
    /// payload, deliberately never `sendMessageData`: the iPhone's existing
    /// `WatchLink.session(_:didReceiveMessageData:)` decodes bare
    /// `LiveTickEnvelope`s with no key, so a raw lifecycle send there would
    /// risk being mis-decoded as a tick. The iPhone receiver for
    /// `lifecycleKey` lands in L3; until then this is harmless —
    /// `WatchLink.session(_:didReceiveMessage:)` simply finds no matching
    /// key and no-ops.
    func send(lifecycle event: LiveSetLifecycleEnvelope) {
        guard let session, let data = try? encoder.encode(event) else {
            logger.error(.watchLink, "lifecycle event encode/send unavailable")
            return
        }

        let payload = [lifecycleKey: data]
        if session.isReachable {
            logger.notice(.watchLink, "sending live set lifecycle event via reachable message")
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.warning(.watchLink, "lifecycle event message failed; queueing userInfo: \(error.localizedDescription)")
                session.transferUserInfo(payload)
            }
        } else {
            logger.notice(.watchLink, "queueing live set lifecycle event userInfo (phone unreachable)")
            session.transferUserInfo(payload)
        }
    }

    func send(finishedSession envelope: SessionEnvelope) {
        guard let session, let data = try? encoder.encode(envelope) else {
            logger.error(.watchLink, "finished session encode/send unavailable")
            return
        }

        let payload = [finishedSessionKey: data]
        if session.isReachable {
            logger.notice(.watchLink, "sending finished session via reachable message id=\(envelope.id)")
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                self?.queueFinishedSession(data, through: session)
            }
        } else {
            logger.notice(.watchLink, "queueing finished session userInfo id=\(envelope.id)")
            queueFinishedSession(data, through: session)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        logger.info(.watchLink, "Watch WCSession activation state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none")")
        updateSessionState(isReachable: session.isReachable, activationState: activationState.rawValue)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info(.watchLink, "Watch WCSession reachability changed reachable=\(session.isReachable)")
        updateSessionState(isReachable: session.isReachable, activationState: session.activationState.rawValue)
    }

    /// Pushes a fresh `WCSession` snapshot onto the `@Observable` state so
    /// `PhoneConnectionChip` updates reactively. Delegate callbacks aren't
    /// guaranteed to land on the main actor, so hop explicitly (mirrors
    /// `WatchLink.pushSessionState` on the iPhone side).
    private func updateSessionState(isReachable: Bool, activationState: Int) {
        Task { @MainActor in
            self.isReachable = isReachable
            self.activationState = activationState
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[payloadKey] as? Data {
            logger.info(.watchLink, "received planned session application context")
            store(data)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[payloadKey] as? Data {
            logger.info(.watchLink, "received planned session userInfo")
            store(data)
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        logger.info(.watchLink, "received planned session live message")
        store(messageData)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let data = message[commandKey] as? Data {
            receiveCommand(data)
            replyHandler([commandKey: "ack"])
            return
        }

        replyHandler([:])
    }

    private func receiveCommand(_ data: Data) {
        guard let command = try? decoder.decode(WatchCommandEnvelope.self, from: data) else {
            logger.error(.watchLink, "failed decoding watch command")
            return
        }

        Task { @MainActor in
            WatchCommandCenter.shared.receive(command, logger: logger)
        }
    }

    private func store(_ data: Data) {
        guard let envelope = try? decoder.decode(PlannedSessionEnvelope.self, from: data) else {
            logger.error(.watchLink, "failed decoding planned session")
            return
        }

        lock.lock()
        plannedSession = envelope
        lock.unlock()
        logger.notice(.watchLink, "stored planned session id=\(envelope.id) sets=\(envelope.sets.count)")

        if let encoded = try? encoder.encode(envelope) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }

        // A freshly received session always restarts the cursor at set 1 —
        // this is a new day's plan (or an edited Session Override resend),
        // not a resume of wherever the previous one left off.
        let freshCursor = PlannedSessionCursor(session: envelope)
        Task { @MainActor in
            self.cursor = freshCursor
        }
    }

    private func queueFinishedSession(_ data: Data, through session: WCSession) {
        logger.info(.watchLink, "transferring finished session userInfo bytes=\(data.count)")
        session.transferUserInfo([finishedSessionKey: data])
    }

    /// A live tick send completed successfully. Frees the coalescer's
    /// in-flight slot; if a fresher tick had arrived while this one was in
    /// flight, it's the pending-latest — send it right away (no backoff:
    /// the transport is healthy).
    private func markLiveTickDelivered(through session: WCSession) {
        lock.lock()
        let next = liveTickCoalescer.completed()
        lock.unlock()

        if let next {
            transmit(next, through: session)
        }
    }

    /// A live tick send failed. Frees the coalescer's in-flight slot the
    /// same way `completed()` does; if a pending-latest tick was waiting,
    /// retry it after a small fixed backoff (not the old 5 s hard delay) so
    /// a flaky link doesn't hot-loop, while still never dropping the
    /// freshest tick.
    private func markLiveTickFailed(_ error: Error, through session: WCSession) {
        lock.lock()
        let next = liveTickCoalescer.failed()
        lock.unlock()

        logger.warning(.watchLink, "live tick send failed: \(error.localizedDescription)")

        guard let next else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + liveTickRetryBackoff) { [weak self] in
            self?.transmit(next, through: session)
        }
    }

    /// Shared failure path for a send that never reached `sendMessageData`
    /// (e.g. encode failure) — frees the coalescer slot and flushes any
    /// pending-latest tick immediately, since the failure was local and
    /// unrelated to link health.
    private func freeLiveTickSlotAndFlushPending(through session: WCSession) {
        lock.lock()
        let next = liveTickCoalescer.failed()
        lock.unlock()

        if let next {
            transmit(next, through: session)
        }
    }

    #if DEBUG
    /// Preview/test-only seam: seeds the cursor directly, bypassing the
    /// `WCSession` decode round-trip, so `#Preview`s can render "no
    /// session" / "next set ready" / "mid-session" states deterministically
    /// without a live phone connection. No production call site.
    func debugSeedCursor(_ cursor: PlannedSessionCursor?) {
        self.cursor = cursor
    }
    #endif
}
