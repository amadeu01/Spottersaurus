//
//  SpottersaurusApp.swift
//  Spottersaurus
//
//  Created by Amadeu Cavalcante on 29/06/26.
//

import SwiftUI
import SwiftData
import SpottersaurusKit

@main
struct SpottersaurusApp: App {
    /// The shared SwiftData container, built once from `SpottersaurusKit`'s
    /// schema. Production mirrors to the CloudKit private database; if those
    /// entitlements are missing (e.g. this phase, before they're configured)
    /// we fall back to a local-only store rather than crashing.
    let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }

    /// Build the CloudKit-mirrored container, degrading to a local store and
    /// finally to an in-memory store so the app always comes up.
    private static func makeContainer() -> ModelContainer {
        do {
            return try makeModelContainer(cloudKit: true)
        } catch {
            // CloudKit unavailable (no entitlement / not signed in) — local store.
            if let local = try? makeModelContainer(cloudKit: false) {
                return local
            }
            // Last resort: never block app launch on persistence.
            do {
                return try makeModelContainer(inMemory: true, cloudKit: false)
            } catch {
                fatalError("Failed to build any ModelContainer: \(error)")
            }
        }
    }
}
