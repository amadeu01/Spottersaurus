//
//  SpottersaurusWatchApp.swift
//  Spottersaurus Watch App
//
//  Standalone watchOS executor app. Phase 1 scaffold only — the live
//  session engine, sensor pipeline, and auto-spotter UI land in later phases.
//

import SwiftUI

@main
struct SpottersaurusWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
