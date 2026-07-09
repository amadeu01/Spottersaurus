//
//  AppLoggerTests.swift
//  SpottersaurusKitTests
//
//  Locks LoggerGroup fan-out: one `log(...)` call must reach every sink in
//  the group, in order, unchanged.
//

import XCTest
@testable import SpottersaurusKit

private final class SpyLogger: AppLogger, @unchecked Sendable {
    var calls: [(level: AppLogLevel, category: AppLogCategory, message: String)] = []

    func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        calls.append((level, category, message))
    }
}

final class AppLoggerTests: XCTestCase {

    func testLoggerGroupForwardsASingleLogCallToEverySink() {
        let first = SpyLogger()
        let second = SpyLogger()
        let third = SpyLogger()
        let group = LoggerGroup([first, second, third])

        group.log(.warning, category: .motion, "gravity lost")

        for spy in [first, second, third] {
            XCTAssertEqual(spy.calls.count, 1)
            XCTAssertEqual(spy.calls.first?.level, .warning)
            XCTAssertEqual(spy.calls.first?.category, .motion)
            XCTAssertEqual(spy.calls.first?.message, "gravity lost")
        }
    }

    func testLoggerGroupForwardsMultipleCallsInOrderToEverySink() {
        let first = SpyLogger()
        let second = SpyLogger()
        let group = LoggerGroup([first, second])

        group.notice(.workout, "set completed")
        group.error(.persistence, "save failed")

        for spy in [first, second] {
            XCTAssertEqual(spy.calls.map(\.message), ["set completed", "save failed"])
            XCTAssertEqual(spy.calls.map(\.level), [.notice, .error])
            XCTAssertEqual(spy.calls.map(\.category), [.workout, .persistence])
        }
    }

    func testIPhoneAndWatchGroupsFanOutToOSLogConsoleAndFileSinks() {
        XCTAssertEqual(LoggerGroup.iPhone.sinks.count, 3)
        XCTAssertTrue(LoggerGroup.iPhone.sinks[0] is OSLogLogger)
        XCTAssertTrue(LoggerGroup.iPhone.sinks[1] is ConsoleLogSink)
        XCTAssertTrue(LoggerGroup.iPhone.sinks[2] is FileLogSink)

        XCTAssertEqual(LoggerGroup.watch.sinks.count, 3)
        XCTAssertTrue(LoggerGroup.watch.sinks[0] is OSLogLogger)
        XCTAssertTrue(LoggerGroup.watch.sinks[1] is ConsoleLogSink)
        XCTAssertTrue(LoggerGroup.watch.sinks[2] is FileLogSink)

        if let iPhoneFileSink = LoggerGroup.iPhone.sinks[2] as? FileLogSink {
            XCTAssertEqual(iPhoneFileSink.target, "iphone")
        } else {
            XCTFail("expected a FileLogSink")
        }

        if let watchFileSink = LoggerGroup.watch.sinks[2] as? FileLogSink {
            XCTAssertEqual(watchFileSink.target, "watch")
        } else {
            XCTFail("expected a FileLogSink")
        }
    }

    func testHealthCategoryRoundTripsItsRawValueAndFansOutLikeAnyOtherCategory() {
        XCTAssertEqual(AppLogCategory(rawValue: "health"), .health)
        XCTAssertEqual(AppLogCategory.health.rawValue, "health")

        let spy = SpyLogger()
        let group = LoggerGroup([spy])

        group.info(.health, "authorization requested")

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.category, .health)
    }

    func testSpottersaurusLogFileURLFallsBackToTemporaryDirectoryWhenNoAppGroup() {
        // In the SwiftPM test bundle there is no App Group entitlement, so the
        // helper must fall back to a writable temp directory rather than nil.
        let url = spottersaurusLogFileURL()

        XCTAssertEqual(url.lastPathComponent, "spottersaurus.log")
        XCTAssertTrue(
            url.path.hasPrefix(FileManager.default.temporaryDirectory.path)
                || url.path.contains("group.amadeu.dev.Spottersaurus")
        )
    }
}
