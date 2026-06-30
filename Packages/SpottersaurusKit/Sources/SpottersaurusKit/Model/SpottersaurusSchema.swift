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
