import SwiftUI
import SpottersaurusKit

enum PlannedSessionSendStatus: String, Sendable {
    case ready = "Ready"
    case sent = "Sent"
    case queued = "Queued"
    case standaloneFallback = "Start on Watch"
    case failed = "Failed"
}

enum WatchCommandSendStatus: String, Sendable {
    case sent = "Sent"
    case watchUnavailable = "Watch unavailable"
    case failed = "Failed"
}

struct PlannerDependencies {
    var logger: LoggerGroup
    var sendPlannedSessionToWatch: @MainActor (Program, ProgramDay, [UserMaxes]) async -> PlannedSessionSendStatus
    var sendWatchCommand: @MainActor (WatchCommandEnvelope.Kind) async -> WatchCommandSendStatus

    static let live = PlannerDependencies(
        logger: .iPhone,
        sendPlannedSessionToWatch: { program, day, maxes in
            let envelope = PlannedSessionEnvelope.make(program: program, day: day, maxes: maxes)
            LoggerGroup.iPhone.notice(.watchLink, "sending planned session id=\(envelope.id) sets=\(envelope.sets.count)")
            let status = await WatchLink.shared.send(plannedSession: envelope)
            LoggerGroup.iPhone.info(.watchLink, "planned session send status=\(status.rawValue)")
            return status
        },
        sendWatchCommand: { command in
            LoggerGroup.iPhone.notice(.watchLink, "sending watch command kind=\(command.rawValue)")
            let status = await WatchLink.shared.send(command: WatchCommandEnvelope(kind: command))
            LoggerGroup.iPhone.info(.watchLink, "watch command send status=\(status.rawValue)")
            return status
        }
    )
}

private struct PlannerDependenciesKey: EnvironmentKey {
    static let defaultValue = PlannerDependencies.live
}

extension EnvironmentValues {
    var plannerDependencies: PlannerDependencies {
        get { self[PlannerDependenciesKey.self] }
        set { self[PlannerDependenciesKey.self] = newValue }
    }
}
