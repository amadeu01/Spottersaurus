import SwiftUI
import SpottersaurusKit

enum PlannedSessionSendStatus: String, Sendable {
    case ready = "Ready"
    case sent = "Sent"
    case queued = "Queued"
    case standaloneFallback = "Start on Watch"
    case failed = "Failed"
}

struct PlannerDependencies {
    var sendPlannedSessionToWatch: @MainActor (Program, ProgramDay, [UserMaxes]) async -> PlannedSessionSendStatus

    static let live = PlannerDependencies { program, day, maxes in
        let envelope = PlannedSessionEnvelope.make(program: program, day: day, maxes: maxes)
        return await WatchLink.shared.send(plannedSession: envelope)
    }
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
