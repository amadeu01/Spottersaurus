import SwiftUI

struct WatchRootView: View {
    @Environment(\.watchDependencies) private var dependencies

    var body: some View {
        LiveSetView(plannedSet: dependencies.currentPlannedSet())
    }
}

#Preview {
    WatchRootView()
}
