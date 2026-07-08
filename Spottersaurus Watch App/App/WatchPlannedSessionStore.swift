import Foundation
import WatchConnectivity
import SpottersaurusKit

final class WatchPlannedSessionStore: NSObject, WCSessionDelegate {
    static let shared = WatchPlannedSessionStore()

    private let payloadKey = "plannedSession"
    private let liveTickKey = "liveTick"
    private let finishedSessionKey = "finishedSession"
    private let defaultsKey = "Spottersaurus.lastPlannedSession"
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var plannedSession: PlannedSessionEnvelope?
    private var session: WCSession?
    private var isLiveTickInFlight = false
    private var liveTickBackoffUntil: Date?
    private let logger = LoggerGroup.watch

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

    func currentPlannedSet() -> PlannedSetEnvelope {
        lock.lock()
        let set = plannedSession?.firstSet
        lock.unlock()

        return set ?? PlannedSetEnvelope(
            lift: .bench,
            exerciseName: "Bench Press",
            targetReps: 5,
            weightKg: 100,
            restSeconds: 90
        )
    }

    func send(liveTick: LiveTickEnvelope) {
        guard let session, session.isReachable, let data = try? encoder.encode(liveTick) else {
            logger.debug(.watchLink, "skipping live tick; phone not reachable or encode failed")
            return
        }

        lock.lock()
        let isBackedOff = liveTickBackoffUntil.map { Date() < $0 } ?? false
        guard !isLiveTickInFlight, !isBackedOff else {
            lock.unlock()
            logger.debug(.watchLink, "skipping live tick; send in flight or backed off")
            return
        }
        isLiveTickInFlight = true
        lock.unlock()

        logger.debug(.watchLink, "sending live tick reps=\(liveTick.repCount) velocity=\(liveTick.currentVelocityMS) hr=\(liveTick.heartRateBPM)")
        session.sendMessageData(data) { [weak self] _ in
            self?.markLiveTickDelivered()
        } errorHandler: { [weak self] error in
            self?.markLiveTickFailed(error)
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
    }

    private func queueFinishedSession(_ data: Data, through session: WCSession) {
        logger.info(.watchLink, "transferring finished session userInfo bytes=\(data.count)")
        session.transferUserInfo([finishedSessionKey: data])
    }

    private func markLiveTickDelivered() {
        lock.lock()
        isLiveTickInFlight = false
        liveTickBackoffUntil = nil
        lock.unlock()
    }

    private func markLiveTickFailed(_ error: Error) {
        lock.lock()
        isLiveTickInFlight = false
        liveTickBackoffUntil = Date().addingTimeInterval(5)
        lock.unlock()
        logger.warning(.watchLink, "live tick send failed: \(error.localizedDescription)")
    }
}
