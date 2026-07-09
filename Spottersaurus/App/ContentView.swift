import SwiftUI
import SpottersaurusKit

struct ContentView: View {
    let storeTier: StoreTier

    @State private var showSplash = true

    init(storeTier: StoreTier = .local) {
        self.storeTier = storeTier
    }

    var body: some View {
        ZStack {
            PlannerTabsView()
            if showSplash {
                SplashView { showSplash = false }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .overlay(alignment: .top) {
            StoreHealthBanner(storeTier: storeTier)
        }
    }
}
