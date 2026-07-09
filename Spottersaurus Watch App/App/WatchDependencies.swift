import SwiftUI
import SpottersaurusKit

struct WatchDependencies {
    var logger: LoggerGroup
    var commandCenter: @MainActor () -> WatchCommandCenter
    var sendLiveTick: @MainActor (LiveTickEnvelope) -> Void
    var sendFinishedSession: @MainActor (SessionEnvelope) -> Void
    /// Emits a Live Set Lifecycle Event (`armed`/`ended`) — see
    /// `WatchPlannedSessionStore.send(lifecycle:)` for the keyed-message
    /// wire detail (never `sendMessageData`).
    var sendLifecycle: @MainActor (LiveSetLifecycleEnvelope) -> Void
    /// Advances the day's set cursor once the current set's rest has fully
    /// elapsed (M1b multi-set execution). `WatchRootView` reads
    /// `WatchPlannedSessionStore.shared.cursor` directly (a reactive
    /// `@Observable` property) rather than through a dependency closure —
    /// this closure only exists for the *mutation*, mirroring
    /// `sendLiveTick`/`sendFinishedSession` above.
    var advanceSessionCursor: @MainActor () -> Void

    static let live = WatchDependencies(
        logger: .watch,
        commandCenter: {
            WatchCommandCenter.shared
        },
        sendLiveTick: { tick in
            LoggerGroup.watch.debug(.watchLink, "sending live tick reps=\(tick.repCount) velocity=\(tick.currentVelocityMS) hr=\(tick.heartRateBPM)")
            WatchPlannedSessionStore.shared.send(liveTick: tick)
        },
        sendFinishedSession: { session in
            LoggerGroup.watch.notice(.watchLink, "sending finished session id=\(session.id) sets=\(session.sets.count)")
            WatchPlannedSessionStore.shared.send(finishedSession: session)
        },
        sendLifecycle: { event in
            LoggerGroup.watch.notice(.watchLink, "sending live set lifecycle event")
            WatchPlannedSessionStore.shared.send(lifecycle: event)
        },
        advanceSessionCursor: {
            WatchPlannedSessionStore.shared.advanceCursor()
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
