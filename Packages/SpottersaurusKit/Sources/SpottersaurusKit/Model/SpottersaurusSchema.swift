//
//  SpottersaurusSchema.swift
//  SpottersaurusKit
//
//  The single shared SwiftData schema both apps consume, plus a container
//  factory. Production builds a CloudKit-mirrored store (private database via
//  `.automatic`, which reads the app's CloudKit entitlement); tests pass
//  `inMemory: true` with CloudKit off so model tests run headless on macOS.
//
//  This layer never hard-fails on missing CloudKit entitlements — it just
//  builds the `ModelConfiguration`. The app target decides whether to fall back
//  to a local store when CloudKit is unavailable.
//

import Foundation
import SwiftData

/// The one schema shared by the iPhone and Watch targets.
public enum SpottersaurusSchema {
    /// Every persistent model in the app, in a stable order.
    public static var all: [any PersistentModel.Type] {
        [
            Exercise.self,
            Program.self,
            ProgramDay.self,
            PlannedSet.self,
            WorkoutSession.self,
            CompletedSet.self,
            RepMetric.self,
            UserMaxes.self,
            CalibrationProfile.self,
            SpotterPairing.self,
            BodyWeightEntry.self,
        ]
    }

    /// The composed SwiftData `Schema`.
    public static var schema: Schema { Schema(all) }
}

/// Build a `ModelContainer` for the shared schema.
///
/// - Parameters:
///   - inMemory: store nothing on disk (tests / previews). Forces CloudKit off.
///   - cloudKit: mirror to the CloudKit **private** database (`.automatic`,
///     resolved from the app's entitlement). Ignored when `inMemory` is true.
/// - Returns: a configured container.
/// - Throws: rethrows `ModelContainer` initialisation errors. Callers that want
///   a graceful local fallback when CloudKit is unavailable should catch and
///   retry with `cloudKit: false`.
public func makeModelContainer(inMemory: Bool = false, cloudKit: Bool = true) throws -> ModelContainer {
    let schema = SpottersaurusSchema.schema
    let configuration: ModelConfiguration

    if inMemory {
        configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    } else if cloudKit {
        // `.automatic` mirrors to the CloudKit private database using the
        // container declared in the app's entitlement.
        configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
    } else {
        configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
    }

    return try ModelContainer(for: schema, configurations: [configuration])
}

/// Which storage tier the app is actually persisting to. Ordered by
/// preference: `.cloudKit` (mirrored, syncs across devices), `.local`
/// (on-disk, this device only), `.inMemory` (lost on relaunch — a red flag
/// that should surface in the UI, see Phase 0 Block B).
public enum StoreTier: String, Sendable, Equatable {
    case cloudKit
    case local
    case inMemory
}

/// Runs the same cloudKit → local → inMemory fallback ladder
/// `SpottersaurusApp.makeContainer()` has always used, but as a pure,
/// injectable function so it's testable without real CloudKit: the caller
/// hands in the container factory (production passes `makeModelContainer`;
/// tests pass a fake that fails on demand) and a logger. Every fallback
/// (including the failure that triggered it) is logged under `.persistence`,
/// and the winning tier is both logged and returned alongside the container
/// so callers (e.g. the app's `@main` struct) can surface it in the UI.
///
/// - Parameters:
///   - makeContainer: builds a container for the given `(inMemory, cloudKit)`
///     flags, matching `makeModelContainer(inMemory:cloudKit:)`'s signature.
///     Injected so tests can force failures deterministically.
///   - logger: destination for the `.persistence` tier/fallback log lines.
/// - Returns: the resolved container plus which tier produced it.
/// - Note: if even the `inMemory` attempt throws, this `fatalError`s exactly
///   like the previous `SpottersaurusApp.makeContainer()` did — there is no
///   lower tier to fall back to and the app cannot launch without *some*
///   container. Callers should ensure their `inMemory` factory branch cannot
///   fail (as `makeModelContainer(inMemory: true, cloudKit: false)` doesn't
///   in practice), which is exactly what the test suite's fakes do, so this
///   path is intentionally never exercised in tests.
public func resolveModelContainer(
    makeContainer: (_ inMemory: Bool, _ cloudKit: Bool) throws -> ModelContainer,
    logger: any AppLogger
) throws -> (container: ModelContainer, tier: StoreTier) {
    do {
        let container = try makeContainer(false, true)
        logger.notice(.persistence, "Store tier resolved: cloudKit")
        return (container, .cloudKit)
    } catch {
        logger.error(.persistence, "cloudKit store failed, falling back to local: \(error)")
    }

    do {
        let container = try makeContainer(false, false)
        logger.notice(.persistence, "Store tier resolved: local")
        return (container, .local)
    } catch {
        logger.error(.persistence, "local store failed, falling back to inMemory: \(error)")
    }

    do {
        let container = try makeContainer(true, false)
        logger.notice(.persistence, "Store tier resolved: inMemory (data will NOT be saved)")
        return (container, .inMemory)
    } catch {
        fatalError("Failed to build any ModelContainer: \(error)")
    }
}
