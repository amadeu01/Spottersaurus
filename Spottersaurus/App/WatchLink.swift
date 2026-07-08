import Foundation
import WatchConnectivity
import SpottersaurusKit

final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private let payloadKey = "plannedSession"
    private let commandKey = "watchCommand"
    private let finishedSessionKey = "finishedSession"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = LoggerGroup.iPhone
    @MainActor private var onFinishedSession: ((SessionEnvelope) -> Void)?
    @MainActor private var onLiveTick: ((LiveTickEnvelope) -> Void)?
    private var session: WCSession?

    override private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        if WCSession.isSupported() {
            self.session = WCSession.default
        }
        super.init()
        session?.delegate = self
        session?.activate()
        logger.info(.watchLink, "activated iPhone WCSession supported=\(session != nil)")
    }

    @MainActor
    func send(command: WatchCommandEnvelope) async -> WatchCommandSendStatus {
        guard let session, session.isReachable else {
            logger.warning(.watchLink, "watch command unavailable reachable=\(session?.isReachable ?? false)")
            return .watchUnavailable
        }

        let data: Data
        do {
            data = try encoder.encode(command)
        } catch {
            logger.error(.watchLink, "watch command encode failed: \(error.localizedDescription)")
            return .failed
        }

        return await withCheckedContinuation { continuation in
            session.sendMessage([commandKey: data]) { _ in
                self.logger.notice(.watchLink, "watch command acknowledged kind=\(command.kind.rawValue)")
                continuation.resume(returning: .sent)
            } errorHandler: { error in
                self.logger.warning(.watchLink, "watch command failed: \(error.localizedDescription)")
                continuation.resume(returning: .failed)
            }
        }
    }

    @MainActor
    func configure(
        onLiveTick: ((LiveTickEnvelope) -> Void)? = nil,
        onFinishedSession: ((SessionEnvelope) -> Void)? = nil
    ) {
        self.onLiveTick = onLiveTick
        self.onFinishedSession = onFinishedSession
    }

    @MainActor
    func send(plannedSession: PlannedSessionEnvelope) async -> PlannedSessionSendStatus {
        guard let session else {
            logger.warning(.watchLink, "WCSession unsupported; using standalone fallback")
            return .standaloneFallback
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            logger.warning(.watchLink, "watch unavailable paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
            return .standaloneFallback
        }

        let data: Data
        do {
            data = try encoder.encode(plannedSession)
        } catch {
            logger.error(.watchLink, "planned session encode failed: \(error.localizedDescription)")
            return .failed
        }

        if session.isReachable {
            logger.info(.watchLink, "sending planned session live bytes=\(data.count)")
            return await sendLive(data, through: session)
        }

        do {
            try session.updateApplicationContext([payloadKey: data])
            logger.info(.watchLink, "queued planned session via application context bytes=\(data.count)")
            return .queued
        } catch {
            session.transferUserInfo([payloadKey: data])
            logger.warning(.watchLink, "application context failed; queued planned session userInfo: \(error.localizedDescription)")
            return .queued
        }
    }

    @MainActor
    private func sendLive(_ data: Data, through session: WCSession) async -> PlannedSessionSendStatus {
        await withCheckedContinuation { continuation in
            session.sendMessageData(data) { _ in
                self.logger.info(.watchLink, "planned session live send acknowledged")
                continuation.resume(returning: .sent)
            } errorHandler: { _ in
                do {
                    try session.updateApplicationContext([self.payloadKey: data])
                    self.logger.info(.watchLink, "planned session live send failed; queued application context")
                    continuation.resume(returning: .queued)
                } catch {
                    session.transferUserInfo([self.payloadKey: data])
                    self.logger.warning(.watchLink, "planned session live/context failed; queued userInfo: \(error.localizedDescription)")
                    continuation.resume(returning: .queued)
                }
            }
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        logger.info(.watchLink, "iPhone WCSession activation state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none")")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        logger.info(.watchLink, "iPhone WCSession deactivated; reactivating")
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        receiveLiveTick(messageData)
    }

    func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        receiveLiveTick(messageData)
        replyHandler(Data())
    }

    private func receiveLiveTick(_ messageData: Data) {
        guard let tick = try? decoder.decode(LiveTickEnvelope.self, from: messageData) else {
            logger.error(.watchLink, "failed decoding live tick")
            return
        }
        logger.debug(.watchLink, "received live tick reps=\(tick.repCount) velocity=\(tick.currentVelocityMS) hr=\(tick.heartRateBPM)")
        Task { @MainActor in
            onLiveTick?(tick)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message[finishedSessionKey] as? Data {
            logger.notice(.watchLink, "received finished session live message bytes=\(data.count)")
            receiveFinishedSession(data)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[finishedSessionKey] as? Data {
            logger.notice(.watchLink, "received finished session userInfo bytes=\(data.count)")
            receiveFinishedSession(data)
        }
    }

    private func receiveFinishedSession(_ data: Data) {
        guard let envelope = try? decoder.decode(SessionEnvelope.self, from: data) else {
            logger.error(.watchLink, "failed decoding finished session")
            return
        }
        logger.notice(.watchLink, "decoded finished session id=\(envelope.id) sets=\(envelope.sets.count)")
        Task { @MainActor in
            onFinishedSession?(envelope)
        }
    }
}
