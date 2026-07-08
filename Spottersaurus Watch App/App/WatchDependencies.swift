import SwiftUI
import SpottersaurusKit

struct WatchDependencies {
    var logger: LoggerGroup
    var currentPlannedSet: @MainActor () -> PlannedSetEnvelope
    var sendLiveTick: @MainActor (LiveTickEnvelope) -> Void
    var sendFinishedSession: @MainActor (SessionEnvelope) -> Void

    static let live = WatchDependencies(
        logger: .watch,
        currentPlannedSet: {
            LoggerGroup.watch.info(.watchLink, "loading current planned set")
            return WatchPlannedSessionStore.shared.currentPlannedSet()
        },
        sendLiveTick: { tick in
            LoggerGroup.watch.debug(.watchLink, "sending live tick reps=\(tick.repCount) velocity=\(tick.currentVelocityMS) hr=\(tick.heartRateBPM)")
            WatchPlannedSessionStore.shared.send(liveTick: tick)
        },
        sendFinishedSession: { session in
            LoggerGroup.watch.notice(.watchLink, "sending finished session id=\(session.id) sets=\(session.sets.count)")
            WatchPlannedSessionStore.shared.send(finishedSession: session)
        }
    )
}

private struct WatchDependenciesKey: EnvironmentKey {
    static let defaultValue = WatchDependencies.live
}

extension EnvironmentValues {
    var watchDependencies: WatchDependencies {
        get { self[WatchDependenciesKey.self] }
        set { self[WatchDependenciesKey.self] = newValue }
    }
}
