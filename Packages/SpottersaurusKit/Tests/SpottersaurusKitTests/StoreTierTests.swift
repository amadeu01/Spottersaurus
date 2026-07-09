//
//  StoreTierTests.swift
//  SpottersaurusKitTests
//
//  Locks the cloudKit → local → inMemory fallback ladder in
//  `resolveModelContainer`: the winning tier is returned *and* logged under
//  `.persistence`, with each caught fallback error also logged, all without
//  touching real CloudKit (the factory closure is injected).
//

import XCTest
import SwiftData
@testable import SpottersaurusKit

private final class SpyLogger: AppLogger, @unchecked Sendable {
    var calls: [(level: AppLogLevel, category: AppLogCategory, message: String)] = []

    func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        calls.append((level, category, message))
    }
}

private struct StubError: Error {}

final class StoreTierTests: XCTestCase {

    func testCloudKitSuccessResolvesToCloudKitTierAndLogsIt() throws {
        let logger = SpyLogger()

        let result = try resolveModelContainer(
            makeContainer: { inMemory, cloudKit in
                try makeModelContainer(inMemory: true, cloudKit: false)
            },
            logger: logger
        )

        XCTAssertEqual(result.tier, .cloudKit)
        XCTAssertTrue(
            logger.calls.contains { $0.category == .persistence && $0.message.contains("cloudKit") }
        )
    }

    func testCloudKitFailureFallsBackToLocalTierAndLogsFallback() throws {
        let logger = SpyLogger()

        let result = try resolveModelContainer(
            makeContainer: { inMemory, cloudKit in
                if cloudKit { throw StubError() }
                return try makeModelContainer(inMemory: true, cloudKit: false)
            },
            logger: logger
        )

        XCTAssertEqual(result.tier, .local)
        XCTAssertTrue(
            logger.calls.contains { $0.category == .persistence && $0.level == .error },
            "expected the cloudKit failure to be logged as an error under .persistence"
        )
        XCTAssertTrue(
            logger.calls.contains { $0.category == .persistence && $0.message.contains("local") }
        )
    }

    func testCloudKitAndLocalFailureFallsBackToInMemoryTierAndLogsBoth() throws {
        let logger = SpyLogger()

        let result = try resolveModelContainer(
            makeContainer: { inMemory, cloudKit in
                if inMemory {
                    return try makeModelContainer(inMemory: true, cloudKit: false)
                }
                throw StubError()
            },
            logger: logger
        )

        XCTAssertEqual(result.tier, .inMemory)
        let errorLogs = logger.calls.filter { $0.category == .persistence && $0.level == .error }
        XCTAssertEqual(errorLogs.count, 2, "expected both the cloudKit and local failures logged")
        XCTAssertTrue(
            logger.calls.contains { $0.category == .persistence && $0.message.contains("inMemory") }
        )
    }
}
