import Foundation
import OSLog

public enum AppLogLevel: Sendable, Equatable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

public enum AppLogCategory: String, Sendable, Equatable {
    case calibration
    case liveSet
    case motion
    case persistence
    case watchLink
    case workout
}

public protocol AppLogger: Sendable {
    func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String)
}

public extension AppLogger {
    func debug(_ category: AppLogCategory, _ message: String) {
        log(.debug, category: category, message)
    }

    func info(_ category: AppLogCategory, _ message: String) {
        log(.info, category: category, message)
    }

    func notice(_ category: AppLogCategory, _ message: String) {
        log(.notice, category: category, message)
    }

    func warning(_ category: AppLogCategory, _ message: String) {
        log(.warning, category: category, message)
    }

    func error(_ category: AppLogCategory, _ message: String) {
        log(.error, category: category, message)
    }
}

public struct LoggerGroup: AppLogger, Sendable {
    public var sinks: [any AppLogger]

    public init(_ sinks: [any AppLogger]) {
        self.sinks = sinks
    }

    public func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        for sink in sinks {
            sink.log(level, category: category, message)
        }
    }
}

public struct OSLogLogger: AppLogger, Sendable {
    public var subsystem: String

    public init(subsystem: String) {
        self.subsystem = subsystem
    }

    public func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .notice:
            logger.notice("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        }
    }
}

/// Identifier of the App Group shared between the iPhone and Watch apps, used
/// so both targets' `FileLogSink`s can append to (and export from) the same
/// on-disk NDJSON file.
public let spottersaurusAppGroupIdentifier = "group.amadeu.dev.Spottersaurus"

/// The maximum size, in bytes, the shared NDJSON log file is allowed to grow
/// to before oldest lines are trimmed.
public let spottersaurusLogFileMaxBytes = 512 * 1024

/// Resolves the shared log file URL inside the App Group container so both
/// apps' `FileLogSink`s write to (and can export from) the same file. Falls
/// back to the caller's temporary directory when the App Group container is
/// unavailable (e.g. unit tests, or a build missing the entitlement), so
/// logging never crashes the app.
public func spottersaurusLogFileURL() -> URL {
    let fileName = "spottersaurus.log"
    if let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: spottersaurusAppGroupIdentifier
    ) {
        return containerURL.appendingPathComponent(fileName)
    }
    return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
}

public extension LoggerGroup {
    static var iPhone: LoggerGroup {
        LoggerGroup([
            OSLogLogger(subsystem: "amadeu.dev.Spottersaurus"),
            ConsoleLogSink(),
            FileLogSink(
                store: FileLogStore(fileURL: spottersaurusLogFileURL(), maxBytes: spottersaurusLogFileMaxBytes),
                target: "iphone"
            )
        ])
    }

    static var watch: LoggerGroup {
        LoggerGroup([
            OSLogLogger(subsystem: "amadeu.dev.Spottersaurus.watchkitapp"),
            ConsoleLogSink(),
            FileLogSink(
                store: FileLogStore(fileURL: spottersaurusLogFileURL(), maxBytes: spottersaurusLogFileMaxBytes),
                target: "watch"
            )
        ])
    }
}
