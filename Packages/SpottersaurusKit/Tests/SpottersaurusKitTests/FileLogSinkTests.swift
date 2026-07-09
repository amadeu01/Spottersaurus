//
//  FileLogSinkTests.swift
//  SpottersaurusKitTests
//
//  Locks the NDJSON on-disk format and ring-cap trimming for FileLogStore, and
//  the synchronous-to-async bridging of FileLogSink.
//

import XCTest
@testable import SpottersaurusKit

final class FileLogSinkTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLogSinkTests-\(UUID().uuidString).ndjson")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        super.tearDown()
    }

    private func makeEntry(_ index: Int, ts: String = "2026-07-09T00:00:00Z") -> LogEntry {
        LogEntry(
            ts: ts,
            level: "info",
            category: "motion",
            target: "watch",
            message: "entry \(index)"
        )
    }

    func testAppendsNEntriesAsOrderedDecodableNDJSONLines() async throws {
        let store = FileLogStore(fileURL: tempURL, maxBytes: 1_000_000)

        for i in 0..<5 {
            await store.append(makeEntry(i))
        }

        let contents = await store.readAll()
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 5)

        let decoder = JSONDecoder()
        let decoded = try lines.map { try decoder.decode(LogEntry.self, from: Data($0.utf8)) }

        for (i, entry) in decoded.enumerated() {
            XCTAssertEqual(entry.message, "entry \(i)")
            XCTAssertEqual(entry.level, "info")
            XCTAssertEqual(entry.category, "motion")
            XCTAssertEqual(entry.target, "watch")
            XCTAssertTrue(entry.ts.hasSuffix("Z") || entry.ts.contains("T"))
        }
    }

    func testEachLineIsASingleJSONObjectWithFieldsInDeclaredOrder() async {
        let store = FileLogStore(fileURL: tempURL, maxBytes: 1_000_000)
        await store.append(makeEntry(0))

        let contents = await store.readAll()
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)

        // Field order is locked: ts, level, category, target, message.
        let tsRange = line.range(of: "\"ts\"")
        let levelRange = line.range(of: "\"level\"")
        let categoryRange = line.range(of: "\"category\"")
        let targetRange = line.range(of: "\"target\"")
        let messageRange = line.range(of: "\"message\"")

        XCTAssertNotNil(tsRange)
        XCTAssertNotNil(levelRange)
        XCTAssertNotNil(categoryRange)
        XCTAssertNotNil(targetRange)
        XCTAssertNotNil(messageRange)

        if let ts = tsRange, let level = levelRange, let category = categoryRange,
           let target = targetRange, let message = messageRange {
            XCTAssertTrue(ts.lowerBound < level.lowerBound)
            XCTAssertTrue(level.lowerBound < category.lowerBound)
            XCTAssertTrue(category.lowerBound < target.lowerBound)
            XCTAssertTrue(target.lowerBound < message.lowerBound)
        }
    }

    func testRingCapTrimsOldestWholeLinesAndKeepsNewestUnderCap() async throws {
        // Each entry serializes to a JSON line whose length is stable and
        // predictable enough to reason about a small maxBytes cap.
        let store = FileLogStore(fileURL: tempURL, maxBytes: 1) // force trimming after every append beyond the first.

        for i in 0..<20 {
            await store.append(makeEntry(i))
        }

        let contents = await store.readAll()
        let sizeOnDisk = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? nil

        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertFalse(lines.isEmpty, "the newest line must survive even if it alone exceeds maxBytes")

        // No partial line: every remaining line must be valid, decodable JSON.
        let decoder = JSONDecoder()
        let decoded = try lines.map { try decoder.decode(LogEntry.self, from: Data($0.utf8)) }

        // The very last entry appended must be the last line retained.
        XCTAssertEqual(decoded.last?.message, "entry 19")

        // Entries must remain in ascending append order (no reordering).
        let messages = decoded.map(\.message)
        XCTAssertEqual(messages, messages.sorted { lhs, rhs in
            let li = Int(lhs.split(separator: " ").last!)!
            let ri = Int(rhs.split(separator: " ").last!)!
            return li < ri
        })

        // Oldest entries must have been dropped since the cap is tiny.
        XCTAssertFalse(messages.contains("entry 0"))

        if let sizeOnDisk {
            // The file itself should not have been allowed to grow unbounded:
            // trimming caps it near a single line's worth of bytes (the
            // newest line is always retained even if it alone exceeds cap).
            let singleLineBytes = try JSONEncoder().encode(makeEntry(19)).count + 1
            XCTAssertLessThanOrEqual(sizeOnDisk, singleLineBytes + 8)
        }
    }

    func testRingCapWithRealisticCapDropsOldestKeepsNewest() async throws {
        // Roughly enough room for ~3 lines; compute a real cap from one entry.
        let sampleLine = try JSONEncoder().encode(makeEntry(0)).count + 1
        let cap = sampleLine * 3

        let store = FileLogStore(fileURL: tempURL, maxBytes: cap)

        for i in 0..<10 {
            await store.append(makeEntry(i))
        }

        let contents = await store.readAll()
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        let decoder = JSONDecoder()
        let decoded = try lines.map { try decoder.decode(LogEntry.self, from: Data($0.utf8)) }
        let messages = decoded.map(\.message)

        XCTAssertEqual(messages.last, "entry 9")
        XCTAssertFalse(messages.contains("entry 0"))
        XCTAssertFalse(messages.contains("entry 1"))

        let sizeOnDisk = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int
        XCTAssertNotNil(sizeOnDisk)
        XCTAssertLessThanOrEqual(sizeOnDisk!, cap)
    }

    func testExportURLReturnsTheBackingFileURL() async {
        let store = FileLogStore(fileURL: tempURL, maxBytes: 1_000_000)
        await store.append(makeEntry(0))

        let exported = await store.exportURL()
        XCTAssertEqual(exported, tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
    }

    func testReadAllOnEmptyStoreReturnsEmptyString() async {
        let store = FileLogStore(fileURL: tempURL, maxBytes: 1_000_000)
        let contents = await store.readAll()
        XCTAssertEqual(contents, "")
    }

    func testFileLogSinkDispatchesAsyncAppendUsingInjectableClock() async throws {
        let store = FileLogStore(fileURL: tempURL, maxBytes: 1_000_000)
        let fixedNow: @Sendable () -> Date = {
            Date(timeIntervalSince1970: 1_752_012_345)
        }
        let sink = FileLogSink(store: store, target: "watch", now: fixedNow)

        sink.log(.warning, category: .motion, "gravity lost")

        // The sink's log() is synchronous and fires an async Task; give the
        // runtime a chance to schedule it, then assert via the actor.
        var contents = await store.readAll()
        var attempts = 0
        while contents.isEmpty && attempts < 100 {
            try await Task.sleep(nanoseconds: 5_000_000)
            contents = await store.readAll()
            attempts += 1
        }

        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(line.isEmpty)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(line.utf8))
        XCTAssertEqual(decoded.level, "warning")
        XCTAssertEqual(decoded.category, "motion")
        XCTAssertEqual(decoded.target, "watch")
        XCTAssertEqual(decoded.message, "gravity lost")

        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(formatter.date(from: decoded.ts))
    }
}
