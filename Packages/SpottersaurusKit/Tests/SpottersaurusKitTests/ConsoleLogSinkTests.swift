//
//  ConsoleLogSinkTests.swift
//  SpottersaurusKitTests
//
//  Locks the console formatting so it stays greppable from Xcode's console
//  filter box, e.g. "[warning][motion] gravity lost".
//

import XCTest
@testable import SpottersaurusKit

final class ConsoleLogSinkTests: XCTestCase {

    func testFormatsWarningMotionEntry() {
        nonisolated(unsafe) var emitted: [String] = []
        let sink = ConsoleLogSink { emitted.append($0) }

        sink.log(.warning, category: .motion, "gravity lost")

        XCTAssertEqual(emitted, ["[warning][motion] gravity lost"])
    }

    func testFormatsNoticeWorkoutEntry() {
        nonisolated(unsafe) var emitted: [String] = []
        let sink = ConsoleLogSink { emitted.append($0) }

        sink.log(.notice, category: .workout, "set completed")

        XCTAssertEqual(emitted, ["[notice][workout] set completed"])
    }

    func testEveryLogLevelMapsToADistinctLowercaseTag() {
        nonisolated(unsafe) var emitted: [String] = []
        let sink = ConsoleLogSink { emitted.append($0) }

        let levels: [AppLogLevel] = [.debug, .info, .notice, .warning, .error, .fault]
        for level in levels {
            sink.log(level, category: .calibration, "x")
        }

        let tags = emitted.map { line -> String in
            // Extract the leading "[tag]" chunk.
            let afterOpen = line.dropFirst() // drop "["
            return String(afterOpen.prefix(while: { $0 != "]" }))
        }

        XCTAssertEqual(tags, ["debug", "info", "notice", "warning", "error", "fault"])
        XCTAssertEqual(Set(tags).count, levels.count, "each level must map to a distinct tag")
        for tag in tags {
            XCTAssertEqual(tag, tag.lowercased())
        }
    }
}
