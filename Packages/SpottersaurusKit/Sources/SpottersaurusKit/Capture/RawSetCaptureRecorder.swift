//
//  RawSetCaptureRecorder.swift
//  SpottersaurusKit
//
//  The pure arm→end accumulator that assembles one working set's
//  `RawSetCapture` (ADR 0008 / PRC-2). It buffers the raw device-motion +
//  heart-rate streams and the lifecycle marker timeline for exactly ONE set at
//  a time — `begin` replaces whatever it was holding, so memory stays bounded
//  to a single set even across a whole workout. Pure Kit type: NO CoreMotion,
//  NO WatchConnectivity, no wall-clock reads of its own (marker timestamps are
//  handed in on the same seconds-since-armed clock the sample streams use), so
//  it is fully unit-testable on macOS. The Watch's `WatchLiveSessionCoordinator`
//  feeds it live samples/markers and the device shell transfers the finished
//  capture as a file when the set ends.
//

import Foundation

/// Accumulates one set's raw sensor stream into a `RawSetCapture`. Not
/// `Sendable` — it is a mutable buffer driven from a single `@MainActor`
/// context on the Watch (the coordinator), and exercised synchronously in
/// tests.
public final class RawSetCaptureRecorder {
    /// The set currently being recorded, or `nil` between `finish()` and the
    /// next `begin(...)`. All mutation funnels through here so that appends /
    /// marks made while no set is active are silently dropped (see
    /// `appendMotion` et al.), which is what lets the coordinator feed the
    /// recorder unconditionally — e.g. during warmup calibration, before the
    /// work set is armed — without leaking pre-arm samples into the capture.
    private struct InProgress {
        let sessionID: UUID
        let setID: UUID
        let setIndex: Int
        let setCount: Int
        let lift: LiftKind
        let armedAt: Date
        var motion: [DeviceMotionSample] = []
        var heartRate: [HRSample] = []
        var markers: [CaptureMarker] = []
    }

    private var inProgress: InProgress?

    public init() {}

    /// Whether a set is currently being recorded (a `begin(...)` has happened
    /// with no matching `finish()` yet). The coordinator forwards motion/HR/
    /// marks unconditionally — appends are cheap no-ops when idle — but reads
    /// this to decide whether a `finish()` is worth calling.
    public var isRecording: Bool { inProgress != nil }

    /// Starts recording a new set, discarding any set still in the buffer.
    /// This reset is what bounds memory to one set at a time. Seeds the
    /// `.armed` marker at `timestamp == 0` so the capture always carries its
    /// first-instant boundary (see `RawSetCapture` / `MarkerKind.armed`)
    /// regardless of what the caller marks afterward.
    public func begin(
        sessionID: UUID,
        setID: UUID,
        setIndex: Int,
        setCount: Int,
        lift: LiftKind,
        armedAt: Date
    ) {
        var started = InProgress(
            sessionID: sessionID,
            setID: setID,
            setIndex: setIndex,
            setCount: setCount,
            lift: lift,
            armedAt: armedAt
        )
        started.markers.append(CaptureMarker(timestamp: 0, kind: .armed))
        inProgress = started
    }

    /// Appends a batch of device-motion samples in arrival order. A no-op when
    /// no set is being recorded (e.g. warmup samples before arm) or the batch
    /// is empty.
    public func appendMotion(_ samples: [DeviceMotionSample]) {
        guard inProgress != nil, !samples.isEmpty else { return }
        inProgress?.motion.append(contentsOf: samples)
    }

    /// Appends one heart-rate sample in arrival order. A no-op when no set is
    /// being recorded.
    public func appendHeartRate(_ sample: HRSample) {
        guard inProgress != nil else { return }
        inProgress?.heartRate.append(sample)
    }

    /// Records a lifecycle boundary on the capture's clock (seconds since
    /// arm — the same origin the sample streams use). A no-op when no set is
    /// being recorded. `timestamp` is clamped to `>= 0` so origin skew between
    /// the marker clock and the motion clock can never place a boundary before
    /// the `.armed` instant.
    public func mark(_ kind: MarkerKind, at timestamp: TimeInterval) {
        guard inProgress != nil else { return }
        inProgress?.markers.append(CaptureMarker(timestamp: max(timestamp, 0), kind: kind))
    }

    /// Seals the current set into a `RawSetCapture` and stops recording, so the
    /// next `begin(...)` starts clean. Returns `nil` when no set is being
    /// recorded (never began, or already finished) — this deliberately returns
    /// an optional rather than the bare `RawSetCapture` a naive reading of the
    /// task might suggest, so the device shell can guard the transfer with a
    /// simple `guard let` instead of tracking `isRecording` itself and risking
    /// a stale/duplicate capture.
    public func finish() -> RawSetCapture? {
        guard let inProgress else { return nil }
        self.inProgress = nil
        return RawSetCapture(
            sessionID: inProgress.sessionID,
            setID: inProgress.setID,
            setIndex: inProgress.setIndex,
            setCount: inProgress.setCount,
            lift: inProgress.lift,
            armedAt: inProgress.armedAt,
            motion: inProgress.motion,
            heartRate: inProgress.heartRate,
            markers: inProgress.markers
        )
    }
}
