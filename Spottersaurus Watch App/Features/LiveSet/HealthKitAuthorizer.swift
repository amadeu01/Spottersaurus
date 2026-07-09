//
//  HealthKitAuthorizer.swift
//  Spottersaurus Watch App
//
//  Concrete `HKHealthStore`-backed `HealthKitAuthorizing` conformer. Lives in
//  the Watch app target (not `SpottersaurusKit`) because HealthKit isn't
//  importable from the shared package — it has no macOS availability, and the
//  package's tests run headless on macOS. The protocol + a fake used to unit
//  test the "ask once" gate live in `SpottersaurusKit`
//  (`HealthKit/HealthKitAuthorizing.swift`); this type is exercised on-device.
//
//  Wired into `WatchWorkoutSessionAdapter.start(...)` as the default
//  `authorizer`, called before `startActivity`/`beginCollection` on first arm.
//

import Foundation
import HealthKit
import SpottersaurusKit

actor HealthKitAuthorizer: HealthKitAuthorizing {
    /// Types the auto-spotter writes back to Apple Health once a set finishes.
    static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.activeEnergyBurned),
        HKObjectType.workoutType(),
    ]

    /// Types the auto-spotter reads live during a set (wrist velocity path
    /// also needs motion, but that's CoreMotion, not HealthKit).
    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
    ]

    private static let hasRequestedDefaultsKey = "HealthKitAuthorizer.hasRequestedAuthorization"

    private let healthStore: HKHealthStore
    private let defaults: UserDefaults

    init(healthStore: HKHealthStore = HKHealthStore(), defaults: UserDefaults = .standard) {
        self.healthStore = healthStore
        self.defaults = defaults
    }

    /// Backed by `UserDefaults` (not just in-memory state) so the gate holds
    /// across relaunches — the Watch app calls this on every set arm and must
    /// not re-prompt after the first attempt, ever.
    var hasRequestedAuthorization: Bool {
        defaults.bool(forKey: Self.hasRequestedDefaultsKey)
    }

    func requestAuthorization() async throws {
        guard !hasRequestedAuthorization else { return }
        defer { defaults.set(true, forKey: Self.hasRequestedDefaultsKey) }
        try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
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
