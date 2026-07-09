//
//  HealthKitAuthorizing.swift
//  SpottersaurusKit
//
//  Platform-neutral abstraction over HealthKit's `requestAuthorization` +
//  authorization-status check, so the "ask once, on first arm" gate the
//  auto-spotter relies on is unit-testable without a live `HKHealthStore`.
//
//  HealthKit itself is not importable from this package (it doesn't exist on
//  macOS, where `swift test` runs the package's tests) — the concrete
//  `HKHealthStore`-backed implementation lives in the Watch app target, next
//  to `WatchWorkoutSessionAdapter`, and conforms to this protocol. It requests
//  exactly the types the auto-spotter needs:
//    - share (write): `HKQuantityType(.activeEnergyBurned)`, `HKObjectType.workoutType()`
//    - read: `HKQuantityType(.heartRate)`
//

import Foundation

/// Mirrors the subset of `HKAuthorizationStatus` callers need, without
/// depending on HealthKit.
public enum HealthAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case sharingDenied
    case sharingAuthorized
}

/// Abstracts the HealthKit authorization request/status pair the auto-spotter
/// depends on: read heart rate (live HR during a set), share workout +
/// active-energy (so a finished set is written back to Apple Health).
///
/// Conformers must gate `requestAuthorization()` so repeated calls (e.g. one
/// per set arm) only prompt the user once — callers are expected to invoke it
/// unconditionally on every arm and rely on the conformer to no-op after the
/// first successful/attempted request.
public protocol HealthKitAuthorizing: Sendable {
    /// Requests the auto-spotter's HealthKit authorization. Safe to call every
    /// time a set arms: implementations no-op after the first invocation.
    func requestAuthorization() async throws

    /// Current read-authorization status for heart rate, so callers can
    /// explain a blank HR readout (denied vs. never asked).
    func authorizationStatusForHeartRate() async -> HealthAuthorizationStatus

    /// Whether `requestAuthorization()` has already been invoked (gate state).
    var hasRequestedAuthorization: Bool { get async }
}
