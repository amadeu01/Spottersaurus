import Foundation
import Observation
import SpottersaurusKit

@MainActor
@Observable
final class WatchCommandCenter {
    static let shared = WatchCommandCenter()

    var latestCommand: WatchCommandEnvelope?

    private init() {}

    func receive(_ command: WatchCommandEnvelope, logger: any AppLogger = LoggerGroup.watch) {
        logger.notice(.watchLink, "received watch command kind=\(command.kind.rawValue) id=\(command.id)")
        latestCommand = command
    }
}
