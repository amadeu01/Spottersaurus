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

    private init() {}

    func receiveLiveTick(_ tick: LiveTickEnvelope) {
        lastTick = tick
        lastTickReceivedAt = Date()
    }

    func recordImport(_ envelope: SessionEnvelope) {
        lastImportedSessionID = envelope.id
        lastImportMessage = "Imported \(envelope.sets.count) set session"
    }
}
