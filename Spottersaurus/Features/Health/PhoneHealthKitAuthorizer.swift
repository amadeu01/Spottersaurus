//
//  PhoneHealthKitAuthorizer.swift
//  Spottersaurus
//
//  Concrete `HKHealthStore`-backed `HealthKitAuthorizing` conformer for the
//  iPhone app. Lives here (not `SpottersaurusKit`) for the same reason the
//  Watch's `HealthKitAuthorizer` does — HealthKit isn't importable from the
//  shared package, whose tests run headless on macOS. The protocol + a fake
//  used to unit test the "ask once" gate live in `SpottersaurusKit`
//  (`HealthKit/HealthKitAuthorizing.swift`); this type is exercised on-device.
//
//  Unlike the Watch conformer (which shares workout + active-energy back to
//  Apple Health so a finished set is logged), this round the iPhone only
//  *reads* — for the upcoming Health import + Profile "Sync with Apple
//  Health" button (H2/H3/P1). It requests no share types.
//

import Foundation
import HealthKit
import SpottersaurusKit

actor PhoneHealthKitAuthorizer: HealthKitAuthorizing {
    /// Types the iPhone reads for the Health import: past workouts (to dedupe
    /// against sessions already in SpottersaurusKit), body weight (for the
    /// Profile body-info section), and heart rate (matches the Watch's read
    /// set, so a shared "HR authorized?" check behaves consistently).
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.bodyMass),
        HKQuantityType(.heartRate),
    ]

    private static let hasRequestedDefaultsKey = "PhoneHealthKitAuthorizer.hasRequestedAuthorization"

    private let healthStore: HKHealthStore
    private let defaults: UserDefaults
    private let logger: any AppLogger

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        defaults: UserDefaults = .standard,
        logger: any AppLogger = LoggerGroup.iPhone
    ) {
        self.healthStore = healthStore
        self.defaults = defaults
        self.logger = logger
    }

    /// Backed by `UserDefaults` (not just in-memory state) so the gate holds
    /// across relaunches — callers are expected to invoke this on every sync
    /// attempt and must not re-prompt after the first attempt, ever.
    var hasRequestedAuthorization: Bool {
        defaults.bool(forKey: Self.hasRequestedDefaultsKey)
    }

    func requestAuthorization() async throws {
        guard !hasRequestedAuthorization else { return }
        defer { defaults.set(true, forKey: Self.hasRequestedDefaultsKey) }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            logger.info(.health, "requestAuthorization succeeded")
        } catch {
            logger.error(.health, "requestAuthorization failed: \(error.localizedDescription)")
            throw error
        }
    }

    func authorizationStatusForHeartRate() async -> HealthAuthorizationStatus {
        switch healthStore.authorizationStatus(for: HKQuantityType(.heartRate)) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .sharingDenied
        case .sharingAuthorized:
            return .sharingAuthorized
        @unknown default:
            return .notDetermined
        }
    }
}
