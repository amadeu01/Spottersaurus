import Foundation
import WatchConnectivity
import SpottersaurusKit

final class WatchPlannedSessionStore: NSObject, WCSessionDelegate {
    static let shared = WatchPlannedSessionStore()

    private let payloadKey = "plannedSession"
    private let defaultsKey = "Spottersaurus.lastPlannedSession"
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var plannedSession: PlannedSessionEnvelope?
    private var session: WCSession?

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

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[payloadKey] as? Data {
            store(data)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[payloadKey] as? Data {
            store(data)
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        store(messageData)
    }

    private func store(_ data: Data) {
        guard let envelope = try? decoder.decode(PlannedSessionEnvelope.self, from: data) else { return }

        lock.lock()
        plannedSession = envelope
        lock.unlock()

        if let encoded = try? encoder.encode(envelope) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }
}
