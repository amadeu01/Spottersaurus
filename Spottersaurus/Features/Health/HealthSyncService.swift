//
//  HealthSyncService.swift
//  Spottersaurus
//
//  H3: ties H1 (`HealthKitAuthorizing`) + H2 (`HealthImporter`) together into
//  one `sync()` the Profile "Sync with Apple Health" button (P1) and
//  pull-to-refresh (X1) will drive: authorize -> read+map -> persist
//  (idempotent, `HealthSyncPersister`) -> stamp `lastSyncedAt` + a status the
//  UI can render directly.
//
//  Lives in the iOS app target (not `SpottersaurusKit`) because its default
//  dependencies are the real `HKHealthStore`-backed conformers
//  (`PhoneHealthKitAuthorizer`, `PhoneHealthDataReader`), which — like those
//  two types themselves — can't live in the package (HealthKit isn't
//  importable on macOS, where package tests run). Both dependencies are
//  injected as the package's platform-neutral protocols, so this service is
//  fully unit-testable with fakes (`SpottersaurusTests/HealthSyncServiceTests`).
//

import Foundation
import SwiftData
import SpottersaurusKit

/// The Health sync lifecycle, in the shape the Profile button/refresh UI can
/// switch over directly.
enum HealthSyncStatus: Sendable, Equatable {
    case idle
    case syncing
    case synced(Date)
    case failed(String)
}

@MainActor
@Observable
final class HealthSyncService {
    private static let lastSyncedAtDefaultsKey = "HealthSyncService.lastSyncedAt"

    private(set) var status: HealthSyncStatus = .idle
    private(set) var lastSyncedAt: Date?

    private let authorizer: any HealthKitAuthorizing
    private let reader: any HealthDataReading
    private let logger: any AppLogger
    private let defaults: UserDefaults

    init(
        authorizer: any HealthKitAuthorizing = PhoneHealthKitAuthorizer(),
        reader: any HealthDataReading = PhoneHealthDataReader(),
        logger: any AppLogger = LoggerGroup.iPhone,
        defaults: UserDefaults = .standard
    ) {
        self.authorizer = authorizer
        self.reader = reader
        self.logger = logger
        self.defaults = defaults
        if let stored = defaults.object(forKey: Self.lastSyncedAtDefaultsKey) as? Date {
            lastSyncedAt = stored
            status = .synced(stored)
        }
    }

    /// Authorizes, reads + maps recent Health data, persists it idempotently
    /// into `context`, and stamps `lastSyncedAt` on success. Never throws —
    /// failures land in `status` so the UI can render them directly. On
    /// failure, `lastSyncedAt` is left untouched and nothing partial is
    /// persisted (persistence only runs after a fully successful import).
    func sync(context: ModelContext) async {
        status = .syncing
        logger.info(.health, "Health sync starting")
        do {
            try await authorizer.requestAuthorization()
            let result = try await HealthImporter(reader: reader).importRecent()
            logger.info(
                .health,
                "Health sync read \(result.workouts.count) workout(s), bodyWeight=\(result.bodyWeight != nil)"
            )
            try HealthSyncPersister.persist(result, into: context)
            let now = Date()
            lastSyncedAt = now
            defaults.set(now, forKey: Self.lastSyncedAtDefaultsKey)
            status = .synced(now)
            logger.notice(.health, "Health sync complete")
        } catch {
            logger.error(.health, "Health sync failed: \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
        }
    }
}
