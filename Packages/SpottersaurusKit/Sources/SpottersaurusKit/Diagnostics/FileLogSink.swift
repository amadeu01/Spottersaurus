//
//  FileLogSink.swift
//  SpottersaurusKit
//
//  Appends structured NDJSON log lines to a file, ring-capped by size, so the
//  log can be exported and read by an LLM or attached to a bug report. The
//  file itself lives out-of-process (the App Group container path is chosen
//  by the caller) so this stays testable against a temp directory.
//

import Foundation

/// One NDJSON log line. Field order is locked via `CodingKeys` so every line
/// on disk is deterministic and diffable.
public struct LogEntry: Codable, Sendable, Equatable {
    public var ts: String
    public var level: String
    public var category: String
    public var target: String
    public var message: String

    private enum CodingKeys: String, CodingKey {
        case ts
        case level
        case category
        case target
        case message
    }

    public init(ts: String, level: String, category: String, target: String, message: String) {
        self.ts = ts
        self.level = level
        self.category = category
        self.target = target
        self.message = message
    }
}

/// Owns the on-disk NDJSON log file: appending, size-capped trimming, and
/// export. Isolated in an actor since file I/O is not safe to interleave
/// across concurrent callers.
public actor FileLogStore {
    private let fileURL: URL
    private let maxBytes: Int
    private let fieldEncoder: JSONEncoder

    public init(fileURL: URL, maxBytes: Int) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.fieldEncoder = JSONEncoder()
    }

    /// Appends one NDJSON line for `entry`, then trims whole oldest lines
    /// from the front of the file until the file size is back under
    /// `maxBytes`. Never leaves a partial line, and always keeps at least
    /// the most recently appended line even if it alone exceeds the cap.
    public func append(_ entry: LogEntry) async {
        do {
            var line = try serialize(entry)
            line.append(UInt8(ascii: "\n"))

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: line)

            try trimIfNeeded()
        } catch {
            // Logging must never crash the app; drop the entry on I/O failure.
        }
    }

    /// Reads the entire NDJSON file back as a UTF-8 string. Returns an empty
    /// string if the file does not exist yet.
    public func readAll() async -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The URL of the backing file, suitable for sharing/exporting.
    public func exportURL() async -> URL {
        fileURL
    }

    /// Serializes `entry` to a single-line JSON object with fields in the
    /// exact locked order `ts, level, category, target, message`.
    ///
    /// `JSONEncoder`'s keyed-container output does not guarantee property
    /// declaration order is preserved on disk, so each field is encoded
    /// individually (guaranteeing correct JSON string escaping) and the
    /// object is composed manually to lock the byte layout.
    private func serialize(_ entry: LogEntry) throws -> Data {
        func jsonString(_ value: String) throws -> String {
            let data = try fieldEncoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        }

        let object = "{\"ts\":\(try jsonString(entry.ts))"
            + ",\"level\":\(try jsonString(entry.level))"
            + ",\"category\":\(try jsonString(entry.category))"
            + ",\"target\":\(try jsonString(entry.target))"
            + ",\"message\":\(try jsonString(entry.message))}"

        return Data(object.utf8)
    }

    /// Trims whole oldest lines from the front of the file until its size is
    /// at or under `maxBytes`. The most recently appended line is always
    /// retained, even if its size alone exceeds `maxBytes`, and no partial
    /// line is ever left on disk.
    private func trimIfNeeded() throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let currentSize = attributes[.size] as? Int,
              currentSize > maxBytes else {
            return
        }

        let data = try Data(contentsOf: fileURL)

        // Split into whole lines (each ending in "\n"). Any bytes after the
        // final "\n" would be a partial line; ignore them defensively (we
        // only ever append complete lines, so this should not occur).
        let newline = UInt8(ascii: "\n")
        var lineRanges: [Range<Data.Index>] = []
        var lineStart = data.startIndex
        var index = data.startIndex
        while index < data.endIndex {
            if data[index] == newline {
                lineRanges.append(lineStart..<(index + 1))
                lineStart = index + 1
            }
            index += 1
        }

        guard let newestLineRange = lineRanges.last else {
            return
        }

        // Drop oldest whole lines until the remainder fits, always keeping
        // at least the newest line even if it alone exceeds maxBytes.
        var keptRanges = lineRanges
        var totalSize = keptRanges.reduce(0) { $0 + $1.count }

        while totalSize > maxBytes, keptRanges.count > 1 {
            let dropped = keptRanges.removeFirst()
            totalSize -= dropped.count
        }

        if keptRanges.isEmpty {
            keptRanges = [newestLineRange]
        }

        guard keptRanges.count < lineRanges.count else {
            // Nothing to drop.
            return
        }

        var trimmedData = Data()
        trimmedData.reserveCapacity(keptRanges.reduce(0) { $0 + $1.count })
        for range in keptRanges {
            trimmedData.append(data[range])
        }

        try trimmedData.write(to: fileURL, options: .atomic)
    }
}

/// Synchronous `AppLogger` conformance that bridges into the async
/// `FileLogStore` actor via a fire-and-forget `Task`. `target` (e.g. "iphone"
/// / "watch") and `now` (an injectable clock) are captured at init for
/// deterministic tests.
public struct FileLogSink: AppLogger, Sendable {
    public var store: FileLogStore
    public var target: String
    public var now: @Sendable () -> Date

    public init(store: FileLogStore, target: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.target = target
        self.now = now
    }

    public func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        let entry = LogEntry(
            ts: ISO8601DateFormatter().string(from: now()),
            level: level.fileLogTag,
            category: category.rawValue,
            target: target,
            message: message
        )
        let store = store
        Task {
            await store.append(entry)
        }
    }
}

private extension AppLogLevel {
    var fileLogTag: String {
        switch self {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .warning: return "warning"
        case .error: return "error"
        case .fault: return "fault"
        }
    }
}
