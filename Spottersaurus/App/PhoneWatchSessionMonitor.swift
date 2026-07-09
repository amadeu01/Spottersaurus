import Foundation
import Observation
import SpottersaurusKit

@MainActor
@Observable
final class PhoneWatchSessionMonitor {
    static let shared = PhoneWatchSessionMonitor()

    var lastTick: LiveTickEnvelope?
    var lastTickReceivedAt: Date?
    var lastImportedSessionID: UUID?
    var lastImportMessage = "Waiting for Watch"

    /// Latest `WCSession` state snapshot, pushed by `WatchLink`'s delegate
    /// callbacks. `activationState` mirrors `WCSessionActivationState.rawValue`
    /// (see `ConnectionStatus` for the mapping) so this file doesn't need to
    /// import WatchConnectivity.
    var isReachable = false
    var isPaired = false
    var isWatchAppInstalled = false
    var activationState = 0

    /// Pure projection of the flags above via `ConnectionStatus.resolve`.
    var connectionStatus: ConnectionStatus {
        ConnectionStatus.resolve(
            isPaired: isPaired,
            isWatchAppInstalled: isWatchAppInstalled,
            isReachable: isReachable,
            activationState: activationState
        )
    }

    private init() {}

    func receiveLiveTick(_ tick: LiveTickEnvelope) {
        lastTick = tick
        lastTickReceivedAt = Date()
    }

    func recordImport(_ envelope: SessionEnvelope) {
        lastImportedSessionID = envelope.id
        lastImportMessage = "Imported \(envelope.sets.count) set session"
    }

    /// Called by `WatchLink` whenever a delegate callback observes fresh
    /// `WCSession` state (activation completing, reachability changing, or
    /// after a send attempt that already read these flags).
    func updateSessionState(
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isReachable: Bool,
        activationState: Int
    ) {
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        self.isReachable = isReachable
        self.activationState = activationState
    }
}
