//
//  RawSetCapture.swift
//  SpottersaurusKit
//
//  A versioned, self-contained container for one working set's raw sensor
//  stream (device motion + heart rate + lifecycle markers), from arm through
//  end. See docs/adr/0008-raw-sensor-capture.md: the Watch buffers this
//  arm→end and transfers it to the iPhone as a file (PRC-2/PRC-3) so a set
//  can be reprocessed offline through `SpotEngine` for detection tuning and
//  debugging without touching hardware again. Pure Kit type — no CoreMotion
//  or WatchConnectivity import — so it is fully testable on macOS.
//

import Foundation

/// A single lifecycle boundary observed while recording a set, timestamped on
/// the same clock as the sample streams (seconds since arm). These let a
/// replay line up `SpotEngine`-detected events against ground truth of what
/// actually happened during capture.
public enum MarkerKind: String, Codable, Sendable, CaseIterable {
    /// The set was armed (Start pressed) — the first instant on this
    /// capture's clock; always present at `timestamp == 0`.
    case armed
    /// Unrack/walkout/brace is underway; no rep has been gated yet
    /// (`SetLifecycleState.settling`).
    case settling
    /// The rep-1 gate accepted the first rep (setup is over).
    case firstRep
    /// A rep (second and onward) completed.
    case rep
    /// The bar came to rest after the set's last rep
    /// (`SetLifecycleState.racked`).
    case racked
    /// The rest clock started (`SetLifecycleState.resting`).
    case restStarted
    /// The set is fully complete and capture recording stopped.
    case ended
}

/// One lifecycle boundary on the capture's clock.
public struct CaptureMarker: Codable, Sendable, Equatable {
    /// Seconds since the set was armed — same clock as
    /// `DeviceMotionSample.timestamp` / `HRSample.timestamp`.
    public var timestamp: TimeInterval
    public var kind: MarkerKind

    public init(timestamp: TimeInterval, kind: MarkerKind) {
        self.timestamp = timestamp
        self.kind = kind
    }
}

/// A versioned container holding one set's entire raw sensor stream, from
/// arm through end, for offline reprocessing/debugging (ADR 0008).
///
/// `schemaVersion` is bumped whenever a field is added/removed so that a
/// capture written by an older build still decodes: `init(from:)` below
/// decodes every field added after version 1 with `decodeIfPresent` and a
/// sensible default, rather than relying on synthesized decoding (which
/// would fail-closed on a missing key).
public struct RawSetCapture: Codable, Sendable, Equatable {
    /// Bump when the wire/disk shape changes; decoding stays
    /// backward-compatible (see `init(from:)`).
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int

    /// The workout session this set belongs to.
    public var sessionID: UUID
    /// This specific set.
    public var setID: UUID
    /// This set's position within its exercise (0-based).
    public var setIndex: Int
    /// Total planned sets for this exercise, for display context.
    public var setCount: Int
    public var lift: LiftKind

    /// Wall-clock time the set was armed. Sample/marker timestamps are
    /// relative seconds from this instant, not wall-clock themselves.
    public var armedAt: Date

    public var motion: [DeviceMotionSample]
    public var heartRate: [HRSample]
    /// Lifecycle timeline, relative to `armedAt`. See `MarkerKind`.
    public var markers: [CaptureMarker]

    public init(
        schemaVersion: Int = RawSetCapture.currentSchemaVersion,
        sessionID: UUID,
        setID: UUID,
        setIndex: Int,
        setCount: Int,
        lift: LiftKind,
        armedAt: Date,
        motion: [DeviceMotionSample],
        heartRate: [HRSample],
        markers: [CaptureMarker]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.setID = setID
        self.setIndex = setIndex
        self.setCount = setCount
        self.lift = lift
        self.armedAt = armedAt
        self.motion = motion
        self.heartRate = heartRate
        self.markers = markers
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessionID
        case setID
        case setIndex
        case setCount
        case lift
        case armedAt
        case motion
        case heartRate
        case markers
    }

    /// Custom decode so a payload from an older schema version — one missing
    /// a later-added field entirely — still decodes with a sensible default
    /// rather than throwing. `markers` was added after version 1: an older
    /// capture with no `markers` key decodes as `[]`. `encode(to:)` is left
    /// to synthesis (every field is `Encodable`), so only decoding needs the
    /// custom path.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        setID = try container.decode(UUID.self, forKey: .setID)
        setIndex = try container.decode(Int.self, forKey: .setIndex)
        setCount = try container.decode(Int.self, forKey: .setCount)
        lift = try container.decode(LiftKind.self, forKey: .lift)
        armedAt = try container.decode(Date.self, forKey: .armedAt)
        motion = try container.decodeIfPresent([DeviceMotionSample].self, forKey: .motion) ?? []
        heartRate = try container.decodeIfPresent([HRSample].self, forKey: .heartRate) ?? []
        markers = try container.decodeIfPresent([CaptureMarker].self, forKey: .markers) ?? []
    }
}

// MARK: - Compact binary codec

extension RawSetCapture {
    /// Encodes to a compact binary blob for on-disk storage / `transferFile`.
    ///
    /// Uses `PropertyListEncoder` in `.binary` format rather than
    /// `JSONEncoder`: a set's motion stream is thousands of `Double`s at
    /// 200 Hz (ADR 0008 estimates ~112 bytes/sample), and the binary plist
    /// format stores numeric/date/data values in their native binary
    /// representation instead of JSON's decimal text, which is both smaller
    /// on disk and cheaper to parse back — with zero extra code, since
    /// `PropertyListEncoder`/`Decoder` implement the same `Codable`
    /// container protocols `JSONEncoder` does, so every type here (including
    /// `UUID`, `Date`, and the raw-representable enums) round-trips exactly
    /// with no custom `encode(to:)`/`init(from:)` beyond the
    /// backward-compat decode above.
    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    /// Decodes a blob written by `encoded()` (any schema version this type
    /// knows how to read — see `init(from:)`).
    public init(decoded data: Data) throws {
        let decoder = PropertyListDecoder()
        self = try decoder.decode(RawSetCapture.self, from: data)
    }
}

// MARK: - NDJSON export

/// One NDJSON line kind, tagged by `type` so a line-by-line parser can
/// dispatch without look-ahead. Field layout intentionally mirrors the
/// project's existing NDJSON convention (`Diagnostics/FileLogSink.swift`).
private struct NDJSONHeaderLine: Codable {
    var type = "header"
    var schemaVersion: Int
    var sessionID: UUID
    var setID: UUID
    var setIndex: Int
    var setCount: Int
    var lift: LiftKind
    var armedAt: Date
    var motionCount: Int
    var heartRateCount: Int
    var markerCount: Int
}

private struct NDJSONMotionLine: Codable {
    var type = "motion"
    var t: TimeInterval
    var uaX: Double
    var uaY: Double
    var uaZ: Double
    var gX: Double
    var gY: Double
    var gZ: Double
    var rrX: Double
    var rrY: Double
    var rrZ: Double
    var qw: Double
    var qx: Double
    var qy: Double
    var qz: Double
}

private struct NDJSONHeartRateLine: Codable {
    var type = "hr"
    var t: TimeInterval
    var bpm: Double
}

private struct NDJSONMarkerLine: Codable {
    var type = "marker"
    var t: TimeInterval
    var kind: MarkerKind
}

extension RawSetCapture {
    /// Renders the capture as NDJSON (one JSON object per line) for external
    /// inspection / the LLM debug flow (mirrors `FileLogSink`'s NDJSON
    /// style). Line order: one `header` line (identity + schemaVersion +
    /// armedAt, ISO 8601), then one `motion` line per `DeviceMotionSample`,
    /// one `hr` line per `HRSample`, and one `marker` line per
    /// `CaptureMarker` — every line tagged by `type` so a parser can dispatch
    /// per-line without buffering the whole file.
    public func exportNDJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        func line<T: Encodable>(_ value: T) -> String {
            guard let data = try? encoder.encode(value) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }

        var lines: [String] = []
        lines.reserveCapacity(1 + motion.count + heartRate.count + markers.count)

        lines.append(line(NDJSONHeaderLine(
            schemaVersion: schemaVersion,
            sessionID: sessionID,
            setID: setID,
            setIndex: setIndex,
            setCount: setCount,
            lift: lift,
            armedAt: armedAt,
            motionCount: motion.count,
            heartRateCount: heartRate.count,
            markerCount: markers.count
        )))

        for sample in motion {
            lines.append(line(NDJSONMotionLine(
                t: sample.timestamp,
                uaX: sample.userAccelerationG.x,
                uaY: sample.userAccelerationG.y,
                uaZ: sample.userAccelerationG.z,
                gX: sample.gravityG.x,
                gY: sample.gravityG.y,
                gZ: sample.gravityG.z,
                rrX: sample.rotationRateRadS.x,
                rrY: sample.rotationRateRadS.y,
                rrZ: sample.rotationRateRadS.z,
                qw: sample.attitude.w,
                qx: sample.attitude.x,
                qy: sample.attitude.y,
                qz: sample.attitude.z
            )))
        }

        for sample in heartRate {
            lines.append(line(NDJSONHeartRateLine(t: sample.timestamp, bpm: sample.beatsPerMinute)))
        }

        for marker in markers {
            lines.append(line(NDJSONMarkerLine(t: marker.timestamp, kind: marker.kind)))
        }

        return lines.map { $0 + "\n" }.joined()
    }
}

// MARK: - CSV export

extension RawSetCapture {
    /// The motion stream as CSV — the most useful stream for
    /// spreadsheet/plot inspection (rep timing, velocity, orientation).
    /// Columns: `t, uaX,uaY,uaZ, gX,gY,gZ, rrX,rrY,rrZ, qw,qx,qy,qz`, one row
    /// per `DeviceMotionSample`, header row included.
    public func exportCSV() -> String {
        var lines = ["t,uaX,uaY,uaZ,gX,gY,gZ,rrX,rrY,rrZ,qw,qx,qy,qz"]
        for sample in motion {
            let ua = sample.userAccelerationG
            let g = sample.gravityG
            let rr = sample.rotationRateRadS
            let q = sample.attitude
            lines.append(
                "\(sample.timestamp),\(ua.x),\(ua.y),\(ua.z),"
                    + "\(g.x),\(g.y),\(g.z),"
                    + "\(rr.x),\(rr.y),\(rr.z),"
                    + "\(q.w),\(q.x),\(q.y),\(q.z)"
            )
        }
        return lines.map { $0 + "\n" }.joined()
    }

    /// The heart-rate stream as a separate CSV (different sample rate/length
    /// than motion, so it does not share a row grid with `exportCSV()`).
    /// Columns: `t, bpm`, one row per `HRSample`, header row included.
    public func exportHeartRateCSV() -> String {
        var lines = ["t,bpm"]
        for sample in heartRate {
            lines.append("\(sample.timestamp),\(sample.beatsPerMinute)")
        }
        return lines.map { $0 + "\n" }.joined()
    }
}
