//
//  ConsoleLogSink.swift
//  SpottersaurusKit
//
//  Prints log entries in a format Xcode's console filter box can match by
//  category, e.g. "[warning][motion] gravity lost".
//

import Foundation

public struct ConsoleLogSink: AppLogger, Sendable {
    public var emit: @Sendable (String) -> Void

    public init(emit: @Sendable @escaping (String) -> Void = { print($0) }) {
        self.emit = emit
    }

    public func log(_ level: AppLogLevel, category: AppLogCategory, _ message: String) {
        emit("[\(level.tag)][\(category.rawValue)] \(message)")
    }
}

private extension AppLogLevel {
    var tag: String {
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
