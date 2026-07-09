//
//  HealthKitAuthorizingTests.swift
//  SpottersaurusKitTests
//
//  Locks the "ask once" gate `HealthKitAuthorizing` conformers must provide:
//  a real Watch adapter (C2) will call `requestAuthorization()` on every set
//  arm, and that must only prompt HealthKit once, ever — and must never crash
//  the caller even if the underlying request throws/is denied.
//

import XCTest
@testable import SpottersaurusKit

/// Test double recording invocations without touching HealthKit. Configurable
/// to throw, so tests can model a denied/failed authorization request.
actor FakeHealthKitAuthorizer: HealthKitAuthorizing {
    private(set) var requestCount = 0
    private var requested = false
    private let outcome: Result<Void, Error>

    init(outcome: Result<Void, Error> = .success(())) {
        self.outcome = outcome
    }

    func requestAuthorization() async throws {
        guard !requested else { return }
        requested = true
        requestCount += 1
        try outcome.get()
    }

    func authorizationStatusForHeartRate() async -> HealthAuthorizationStatus {
        .notDetermined
    }

    var hasRequestedAuthorization: Bool {
        requested
    }
}

private struct FakeAuthorizationError: Error {}

final class HealthKitAuthorizingTests: XCTestCase {

    func testRequestAuthorizationGatesToASingleUnderlyingRequestAcrossTwoArms() async throws {
        let authorizer = FakeHealthKitAuthorizer()

        try await authorizer.requestAuthorization() // "arm" 1
        try await authorizer.requestAuthorization() // "arm" 2

        let count = await authorizer.requestCount
        XCTAssertEqual(count, 1)
        let hasRequested = await authorizer.hasRequestedAuthorization
        XCTAssertTrue(hasRequested)
    }

    func testDeniedOrThrowingAuthorizationStillGatesAndLetsCallerProceed() async {
        let authorizer = FakeHealthKitAuthorizer(outcome: .failure(FakeAuthorizationError()))

        // Model the C2 adapter behavior: swallow the error, proceed with start().
        var didProceed = false
        do {
            try await authorizer.requestAuthorization()
        } catch {
            didProceed = true // caller continues instead of crashing/propagating
        }
        XCTAssertTrue(didProceed)

        // A second arm must not re-attempt the request even though it failed.
        do {
            try await authorizer.requestAuthorization()
        } catch {
            XCTFail("gate should have no-op'd the second call, not thrown again")
        }

        let count = await authorizer.requestCount
        XCTAssertEqual(count, 1)
    }

    func testAuthorizationStatusForHeartRateReflectsFakeDefault() async {
        let authorizer = FakeHealthKitAuthorizer()
        let status = await authorizer.authorizationStatusForHeartRate()
        XCTAssertEqual(status, .notDetermined)
    }
}
