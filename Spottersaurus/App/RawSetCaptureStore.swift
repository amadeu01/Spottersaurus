//
//  RawSetCaptureStore.swift
//  Spottersaurus
//
//  iPhone-side receiver + local store for raw sensor captures transferred
//  Watch → iPhone via `WCSession.transferFile` (ADR 0008 / PRC-3). Thin
//  adapter over the pure `RawSetCaptureIndex` in SpottersaurusKit: it copies
//  each transferred file into an Application Support captures directory named
//  by set id, records the identity carried in the transfer metadata, and
//  applies keep-last-N-workouts retention via the Kit index (which decides
//  *what* to delete; this class does the actual file removal). All grouping /
//  retention *logic* lives in Kit and is unit-tested there; this class is the
//  untested device seam (WatchConnectivity + FileManager).
//

import Foundation
import SpottersaurusKit

final class RawSetCaptureStore {
    static let shared = RawSetCaptureStore()

    /// Keep the raw captures of the last N workouts on the phone; older
    /// workouts are pruned as new captures arrive (ADR 0008: raw storage is a
    /// local, prunable debug/tuning asset, not synced user data).
    private let keepLastSessions = 20

    private let logger = LoggerGroup.iPhone
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// In-memory mirror of the on-disk `index.json` sidecar, guarded by
    /// `lock`. Loaded lazily on first access.
    private var loadedIndex: RawSetCaptureIndex?

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: Receive

    /// Accepts a transferred capture file plus its transfer metadata (mirrors
    /// the keys set in `WatchPlannedSessionStore.transfer(rawSetCapture:)`),
    /// copies it into the captures directory named by set id, records its
    /// identity, and applies retention. WatchConnectivity hands us a file in a
    /// temp inbox that is deleted as soon as the delegate call returns, so the
    /// copy must happen synchronously here.
    func receive(fileAt url: URL, metadata: [String: Any]?) {
        guard let metadata, metadata[WireKeys.rawSetCapture] != nil else {
            logger.warning(.watchLink, "received file without raw-set-capture metadata; ignoring")
            return
        }
        guard let identity = Self.identity(from: metadata) else {
            logger.error(.watchLink, "raw set capture metadata malformed; keys=\(metadata.keys.sorted())")
            return
        }

        do {
            let directory = try capturesDirectory()
            let destination = directory.appendingPathComponent(identity.fileName)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            logger.error(.watchLink, "raw set capture copy failed setID=\(identity.setID): \(error.localizedDescription)")
            return
        }

        lock.lock()
        var index = loadIndexLocked()
        index.insert(identity)
        let pruned = index.prune(keepingLastSessions: keepLastSessions)
        saveIndexLocked(index)
        lock.unlock()

        deleteFiles(pruned)
        logger.notice(.watchLink, "stored raw set capture setID=\(identity.setID) session=\(identity.sessionID) lift=\(identity.lift.rawValue) pruned=\(pruned.count)")
    }

    // MARK: Listing

    /// Every capture recorded for a set, newest first (PRC-3 per-set listing).
    func captures(forSet setID: UUID) -> [RawSetCaptureIdentity] {
        lock.lock()
        defer { lock.unlock() }
        return loadIndexLocked().captures(forSet: setID)
    }

    /// The full workout → exercise → set hierarchy for a browse UI.
    func workouts() -> [CaptureWorkoutGroup] {
        lock.lock()
        defer { lock.unlock() }
        return loadIndexLocked().workouts
    }

    /// The on-disk location of a stored capture file, if it exists.
    func fileURL(for identity: RawSetCaptureIdentity) -> URL? {
        guard let directory = try? capturesDirectory() else { return nil }
        let url = directory.appendingPathComponent(identity.fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Decodes a stored capture back into its full `RawSetCapture`, for
    /// replay/inspection.
    func loadCapture(_ identity: RawSetCaptureIdentity) -> RawSetCapture? {
        guard let url = fileURL(for: identity),
              let data = try? Data(contentsOf: url),
              let capture = try? RawSetCapture(decoded: data) else {
            return nil
        }
        return capture
    }

    // MARK: Manual delete

    /// Manually deletes a single stored capture file and forgets its identity.
    func delete(_ identity: RawSetCaptureIdentity) {
        lock.lock()
        var index = loadIndexLocked()
        let removed = index.remove(fileName: identity.fileName)
        saveIndexLocked(index)
        lock.unlock()

        if let removed {
            deleteFiles([removed])
            logger.notice(.watchLink, "manually deleted raw set capture file=\(removed.fileName)")
        }
    }

    /// Manually deletes every stored capture for a set.
    func deleteSet(_ setID: UUID) {
        lock.lock()
        var index = loadIndexLocked()
        let removed = index.removeSet(setID)
        saveIndexLocked(index)
        lock.unlock()

        deleteFiles(removed)
        logger.notice(.watchLink, "manually deleted \(removed.count) raw set capture file(s) for setID=\(setID)")
    }

    // MARK: - Metadata mapping

    /// Reconstructs a `RawSetCaptureIdentity` from the transfer metadata set on
    /// the Watch side. The file is stored one-per-set named by `setID`.
    private static func identity(from metadata: [String: Any]) -> RawSetCaptureIdentity? {
        guard let sessionIDString = metadata["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              let setIDString = metadata["setID"] as? String,
              let setID = UUID(uuidString: setIDString),
              let setIndex = metadata["setIndex"] as? Int,
              let setCount = metadata["setCount"] as? Int,
              let liftString = metadata["lift"] as? String,
              let lift = LiftKind(rawValue: liftString),
              let armedAt = metadata["armedAt"] as? Date else {
            return nil
        }
        return RawSetCaptureIdentity(
            sessionID: sessionID,
            setID: setID,
            setIndex: setIndex,
            setCount: setCount,
            lift: lift,
            armedAt: armedAt,
            fileName: "\(setID.uuidString).plist"
        )
    }

    // MARK: - Storage plumbing

    private func capturesDirectory() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("RawSetCaptures", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private var indexURL: URL? {
        try? capturesDirectory().appendingPathComponent("index.json")
    }

    /// Returns the in-memory index, loading it from the sidecar on first use.
    /// Caller must hold `lock`.
    private func loadIndexLocked() -> RawSetCaptureIndex {
        if let loadedIndex { return loadedIndex }
        let index: RawSetCaptureIndex
        if let indexURL,
           let data = try? Data(contentsOf: indexURL),
           let decoded = try? decoder.decode(RawSetCaptureIndex.self, from: data) {
            index = decoded
        } else {
            index = RawSetCaptureIndex()
        }
        loadedIndex = index
        return index
    }

    /// Persists the index sidecar and updates the in-memory mirror. Caller
    /// must hold `lock`.
    private func saveIndexLocked(_ index: RawSetCaptureIndex) {
        loadedIndex = index
        guard let indexURL else { return }
        do {
            let data = try encoder.encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error(.watchLink, "raw set capture index save failed: \(error.localizedDescription)")
        }
    }

    private func deleteFiles(_ identities: [RawSetCaptureIdentity]) {
        guard let directory = try? capturesDirectory() else { return }
        for identity in identities {
            let url = directory.appendingPathComponent(identity.fileName)
            try? fileManager.removeItem(at: url)
        }
    }
}
