import Foundation
import WatchConnectivity
import SpottersaurusKit

final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private let payloadKey = "plannedSession"
    private let encoder: JSONEncoder
    private var session: WCSession?

    override private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        if WCSession.isSupported() {
            self.session = WCSession.default
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }

    @MainActor
    func send(plannedSession: PlannedSessionEnvelope) async -> PlannedSessionSendStatus {
        guard let session else { return .standaloneFallback }
        guard session.isPaired, session.isWatchAppInstalled else { return .standaloneFallback }

        let data: Data
        do {
            data = try encoder.encode(plannedSession)
        } catch {
            return .failed
        }

        if session.isReachable {
            return await sendLive(data, through: session)
        }

        do {
            try session.updateApplicationContext([payloadKey: data])
            return .queued
        } catch {
            session.transferUserInfo([payloadKey: data])
            return .queued
        }
    }

    @MainActor
    private func sendLive(_ data: Data, through session: WCSession) async -> PlannedSessionSendStatus {
        await withCheckedContinuation { continuation in
            session.sendMessageData(data) { _ in
                continuation.resume(returning: .sent)
            } errorHandler: { _ in
                do {
                    try session.updateApplicationContext([self.payloadKey: data])
                    continuation.resume(returning: .queued)
                } catch {
                    session.transferUserInfo([self.payloadKey: data])
                    continuation.resume(returning: .queued)
                }
            }
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
