import SwiftUI
import SpottersaurusKit

struct WatchDependencies {
    var currentPlannedSet: @MainActor () -> PlannedSetEnvelope

    static let live = WatchDependencies {
        WatchPlannedSessionStore.shared.currentPlannedSet()
    }
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
