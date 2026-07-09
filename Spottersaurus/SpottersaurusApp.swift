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

    /// Which storage tier `modelContainer` actually resolved to. Read by the
    /// UI (Phase 0 Block B2) to show a non-dismissable "not saving" banner
    /// when this is `.inMemory`.
    let storeTier: StoreTier

    init() {
        let resolved = Self.makeContainer()
        modelContainer = resolved.container
        storeTier = resolved.tier
    }

    var body: some Scene {
        WindowGroup {
            ContentView(storeTier: storeTier)
        }
        .modelContainer(modelContainer)
    }

    /// Build the CloudKit-mirrored container, degrading to a local store and
    /// finally to an in-memory store so the app always comes up. The
    /// cloudKit → local → inMemory ladder itself lives in `SpottersaurusKit`
    /// as `resolveModelContainer` so it's testable without real CloudKit;
    /// this just supplies the real factory + the shared iPhone logger.
    private static func makeContainer() -> (container: ModelContainer, tier: StoreTier) {
        try! resolveModelContainer(
            makeContainer: { inMemory, cloudKit in
                try makeModelContainer(inMemory: inMemory, cloudKit: cloudKit)
            },
            logger: LoggerGroup.iPhone
        )
    }
}
