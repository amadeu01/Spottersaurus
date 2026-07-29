import Foundation
import Observation
import SpottersaurusKit

@Observable
final class LiveSetViewModel {
    let exerciseName: String
    let lift: LiftKind
    var targetReps: Int
    var weightKg: Double
    var heartRate: Int
    var velocityMS: Double
    var restElapsed: TimeInterval

    /// This set's zero-based position and the day's total set count within
    /// the Live Session — the "N"/"M" in "Set N of M" (Phase 0.2 M1b). Set
    /// once at construction by `LiveSetView` (which is itself recreated per
    /// set via `.id(current.id)` when the cursor advances), and mirrored
    /// onto every `liveTickEnvelope` so the iPhone mirror shows day
    /// progression, not just per-set state.
    let setIndex: Int
    let setCount: Int

    /// Current HealthKit heart-rate read-authorization status. Refreshed by
    /// `WatchLiveSessionCoordinator` (on screen appear and after each session
    /// start) via `refreshHRAuthStatus(using:)` below — deliberately
    /// read-only from the UI's perspective (`HRAuthIndicatorView` only
    /// renders it) since the setter is private to this type.
    private(set) var hrAuthStatus: HealthAuthorizationStatus = .notDetermined

    private var lifecycle: SetLifecycleController
    private var calibrationState: LiveSetCalibrationState

    /// All sensor-side bookkeeping for this set — rolling motion/HR buffers,
    /// the `SpotEngine` and its calibration, the spot-event dedup gate, and
    /// the telemetry arrival times. It hands back only what's *new* on each
    /// batch; this view model's job is to translate that into lifecycle
    /// transitions and display state (docs/PLAN.md Phase 2 task 10).
    private var sensors: LiveSetSensorAggregator

    private var repMetrics: [RepMetricEnvelope] = []
    private var spotEvents: [SpotEventEnvelope] = []
    private var setStartedAt: Date?
    private let targetWarmupReps = 3

    /// Sink for raw-set-capture lifecycle markers (PRC-2 / ADR 0008),
    /// installed by `WatchLiveSessionCoordinator.beginCapture` while a capture
    /// is in progress and left as a no-op otherwise (previews, tests, no-phone
    /// runs). The VM emits `(kind, secondsSinceArm)` at each lifecycle
    /// boundary via `stepLifecycle` below; the coordinator forwards them into
    /// the `RawSetCaptureRecorder` so the capture's marker timeline stays in
    /// lockstep with the state machine without the VM ever importing
    /// CoreMotion / WatchConnectivity.
    var onCaptureMarker: (MarkerKind, TimeInterval) -> Void = { _, _ in }

    init(
        plannedSet: PlannedSetEnvelope,
        setIndex: Int = 0,
        setCount: Int = 1,
        heartRate: Int = 132,
        velocityMS: Double = 0.42
    ) {
        let fallbackCalibration = CalibrationValues.fallback(for: plannedSet.lift)

        self.exerciseName = plannedSet.exerciseName
        self.lift = plannedSet.lift
        self.targetReps = plannedSet.targetReps
        self.weightKg = plannedSet.weightKg
        self.setIndex = setIndex
        self.setCount = setCount
        self.heartRate = heartRate
        self.velocityMS = velocityMS
        self.restElapsed = 0
        self.lifecycle = SetLifecycleController(restSeconds: TimeInterval(plannedSet.restSeconds))
        self.calibrationState = .fallback(fallbackCalibration)
        self.sensors = LiveSetSensorAggregator(lift: plannedSet.lift, calibration: fallbackCalibration)
    }

    var state: SetLifecycleState {
        lifecycle.state
    }

    var alertStage: AlertStage {
        lifecycle.alertStage
    }

    var repCount: Int {
        lifecycle.repCount
    }

    /// The VEL tile's Mean Concentric Velocity (Phase 0.2 V2): `nil` until the
    /// first rep of the set actually completes (auto-detected or manually
    /// confirmed via `completeRep()`), so the readout can show an honest "--"
    /// instead of `velocityMS`'s placeholder default before any rep exists.
    var displayVelocityMS: Double? {
        repCount > 0 ? velocityMS : nil
    }

    var isRackItOverlayVisible: Bool {
        lifecycle.alertStage == .rackIt
    }

    var isCalibrating: Bool {
        calibrationState.isCollecting
    }

    var calibrationProgress: Double {
        min(Double(currentCalibration.repCount) / Double(targetWarmupReps), 1)
    }

    var calibrationStatusText: String {
        switch calibrationState {
        case .fallback:
            "Baseline fallback"
        case .collecting:
            "Warmup capture"
        case .ready:
            "Baseline ready"
        }
    }

    var calibrationDetailText: String {
        let values = currentCalibration
        guard values.repCount > 0 else {
            return "Capture \(targetWarmupReps) clean warmup reps before the work set."
        }

        let tempo = String(format: "%.2fs", values.baselineConcentricSeconds)
        if lift.usesVelocityPath {
            let lower = String(format: "%.2f", values.velocityBandLowerMS)
            let upper = String(format: "%.2f", values.velocityBandUpperMS)
            return "\(values.repCount) reps, tempo \(tempo), \(lower)-\(upper)m/s"
        }
        return "\(values.repCount) reps, tempo \(tempo)"
    }

    var sensorStatusText: String {
        let samples = sensors.bufferedMotionSampleCount
        guard samples > 0 else { return "Motion: waiting" }
        return "Motion: \(samples) samples"
    }

    /// Live sensor-pipeline health for `PipelineTelemetryView` — proves the
    /// auto-detection is running off real samples, not mocked. `sensorRunning`
    /// isn't tracked by this view model (it doesn't own the motion adapter),
    /// so the caller (typically `WatchLiveSessionCoordinator.isMotionRunning`)
    /// passes it in; samples/sec, HR-flowing, and staleness come from the
    /// aggregator's record of recent wall-clock sample arrivals.
    func telemetry(sensorRunning: Bool, now: Date = Date()) -> LivePipelineTelemetry {
        sensors.telemetry(sensorRunning: sensorRunning, now: now.timeIntervalSinceReferenceDate)
    }

    var liveTickEnvelope: LiveTickEnvelope {
        LiveTickEnvelope(
            repCount: repCount,
            currentVelocityMS: velocityMS,
            heartRateBPM: Double(heartRate),
            elapsedSeconds: setStartedAt.map { max(Date().timeIntervalSince($0), 0) } ?? 0,
            alertStage: alertStage,
            setIndex: setIndex,
            setCount: setCount
        )
    }

    var gaugeProgress: Double {
        if lifecycle.state == .resting || lifecycle.state == .racked {
            return min(max(restElapsed / lifecycle.restSeconds, 0), 1)
        }
        return min(Double(lifecycle.repCount) / Double(max(targetReps, 1)), 1)
    }

    var restText: String {
        guard lifecycle.state == .resting || lifecycle.state == .racked else { return "--" }
        let remaining = max(Int(lifecycle.restSeconds - restElapsed), 0)
        return "\(remaining)s"
    }

    var targetRepsText: String {
        "\(targetReps)"
    }

    var statusText: String {
        switch lifecycle.alertStage {
        case .rackIt:
            "RACK IT"
        case .grinding:
            "GRINDING"
        case .none:
            switch lifecycle.state {
            case .idle: "READY"
            case .settling: "SET UP"
            case .repping: "LIVE"
            case .racked, .resting: "REST"
            case .complete: "SET COMPLETE"
            }
        }
    }

    var statusSymbol: String {
        switch lifecycle.alertStage {
        case .rackIt: "hand.raised.fill"
        case .grinding: "exclamationmark.triangle.fill"
        case .none: lifecycle.state == .resting ? "timer" : "waveform.path.ecg"
        }
    }

    var tone: LiveSetTone {
        switch lifecycle.alertStage {
        case .rackIt: .alert
        case .grinding: .caution
        case .none: .optimal
        }
    }

    /// `armedAt` is injectable so the raw-set capture (PRC-2) and this VM's
    /// marker clock share one arm instant: `WatchLiveSessionCoordinator`
    /// begins the capture with the same `armedAt` it passes here, so a marker
    /// emitted at `secondsSinceArm ≈ 0` lines up with the capture's `armed`
    /// boundary. Defaults to `Date()` so previews/tests keep calling `arm()`.
    func arm(armedAt: Date = Date(), logger: any AppLogger = LoggerGroup.watch) {
        logger.notice(.liveSet, "arming set lift=\(lift.rawValue) targetReps=\(targetReps) weightKg=\(weightKg)")
        calibrationState = .ready(currentCalibration)
        restElapsed = 0
        repMetrics = []
        spotEvents = []
        sensors.arm()
        setStartedAt = armedAt
        // Set `setStartedAt` first: `stepLifecycle` timestamps the resulting
        // `.settling` marker relative to it.
        stepLifecycle { lifecycle.arm() }
    }

    func startWarmupCalibration(logger: any AppLogger = LoggerGroup.watch) {
        logger.notice(.calibration, "starting warmup calibration lift=\(lift.rawValue)")
        sensors.beginWarmupCalibration()
        calibrationState = .collecting(candidate: nil)
    }

    func finishWarmupCalibration(logger: any AppLogger = LoggerGroup.watch) {
        let values = currentCalibration
        guard values.repCount > 0 else {
            logger.warning(.calibration, "warmup calibration had no clean reps; using fallback lift=\(lift.rawValue)")
            calibrationState = .fallback(CalibrationValues.fallback(for: lift))
            sensors.applyCalibration(currentCalibration)
            return
        }

        logger.notice(.calibration, "saved calibration lift=\(lift.rawValue) reps=\(values.repCount) tempo=\(values.baselineConcentricSeconds) lower=\(values.velocityBandLowerMS) upper=\(values.velocityBandUpperMS)")
        calibrationState = .ready(values)
        sensors.applyCalibration(values)
    }

    func completeRep() {
        stepLifecycle { lifecycle.repCompleted() }
        velocityMS = max(0.18, velocityMS - 0.03)
        heartRate += 3
    }

    func rack(logger: any AppLogger = LoggerGroup.watch) {
        logger.notice(.liveSet, "racking set reps=\(repCount)")
        if lifecycle.state == .settling {
            stepLifecycle { lifecycle.repCompleted() }
        }
        stepLifecycle { lifecycle.autoRack() }
        restElapsed = 0
        stepLifecycle { lifecycle.restTick(elapsed: restElapsed) }
    }

    func finishRest(logger: any AppLogger = LoggerGroup.watch) {
        logger.info(.liveSet, "finishing rest")
        restElapsed = lifecycle.restSeconds
        stepLifecycle { lifecycle.restTick(elapsed: restElapsed) }
    }

    func setTargetReps(_ value: Double) {
        targetReps = min(max(Int(value.rounded()), 1), 20)
    }

    func restTick(elapsed: TimeInterval, logger: any AppLogger = LoggerGroup.watch) -> Bool {
        let wasComplete = lifecycle.state == .complete
        restElapsed = elapsed
        stepLifecycle { lifecycle.restTick(elapsed: elapsed) }
        let didComplete = !wasComplete && lifecycle.state == .complete
        if didComplete {
            logger.notice(.liveSet, "rest completed elapsed=\(elapsed)")
        }
        return didComplete
    }

    func finishedSessionEnvelope() -> SessionEnvelope? {
        guard let setStartedAt, repCount > 0 else { return nil }

        let avgVelocity = repMetrics.isEmpty ? velocityMS : repMetrics.map(\.meanVelocityMS).reduce(0, +) / Double(repMetrics.count)
        let peakVelocity = max(repMetrics.map(\.peakVelocityMS).max() ?? 0, velocityMS)
        let completedSet = CompletedSetEnvelope(
            lift: lift,
            startedAt: setStartedAt,
            weightKg: weightKg,
            repsCompleted: repCount,
            repMetrics: repMetrics,
            spotEvents: spotEvents,
            avgConcentricVelocityMS: avgVelocity,
            peakConcentricVelocityMS: peakVelocity
        )
        return SessionEnvelope(date: setStartedAt, sets: [completedSet])
    }

    func resolveAlert() {
        // TODO(P1-1d): increment a manualResolveCount counter here and thread
        // it into finishedSessionEnvelope()'s CompletedSetEnvelope so a
        // manual "Resolved" tap is persisted as a false-alarm signal
        // (SpottersaurusKit's CompletedSetEnvelope.manualResolveCount /
        // CompletedSet.manualResolveCount already support it end-to-end).
        lifecycle.handle(spotEvent: spotEvent(kind: .resolved, confidence: 1, reason: .manualTap))
    }

    func ingestMotionSamples(_ samples: [DeviceMotionSample]) {
        let result = sensors.ingestMotion(
            samples,
            routing: motionRouting,
            at: Date().timeIntervalSinceReferenceDate
        )

        if let candidate = result.calibrationCandidate {
            calibrationState = .collecting(candidate: candidate)
            return
        }

        for rep in result.newReps {
            stepLifecycle { lifecycle.repCompleted() }
            repMetrics.append(
                RepMetricEnvelope(
                    repIndex: rep.repIndex,
                    concentricSeconds: rep.concentricSeconds,
                    peakVelocityMS: rep.peakVelocityMS,
                    meanVelocityMS: rep.meanVelocityMS,
                    romProxy: rep.displacementM,
                    flaggedStall: rep.flaggedStall
                )
            )
            velocityMS = max(0, rep.meanVelocityMS)
        }

        for event in result.newEvents {
            let envelope = SpotEventEnvelope(
                stage: event.kind,
                timestamp: event.timestamp,
                repIndex: event.repIndex,
                confidence: event.confidence,
                reason: event.reason
            )
            if !spotEvents.contains(envelope) {
                spotEvents.append(envelope)
            }
            lifecycle.handle(spotEvent: event)
        }
    }

    /// Where an arriving motion batch belongs, which is a question only this
    /// view model can answer: warmup capture wins if it's running, otherwise
    /// samples only feed detection while a set is actually in flight. Anything
    /// else (idle, racked, resting, complete) is still counted as proof the
    /// sensor is alive, but must not produce reps.
    private var motionRouting: LiveSetSensorAggregator.MotionRouting {
        if calibrationState.isCollecting { return .warmupCalibration }
        switch lifecycle.state {
        case .settling, .repping: return .workingSet
        case .idle, .racked, .resting, .complete: return .telemetryOnly
        }
    }

    func ingestHeartRate(_ sample: HRSample) {
        sensors.ingestHeartRate(sample, at: Date().timeIntervalSinceReferenceDate)
        heartRate = Int(sample.beatsPerMinute.rounded())
    }

    /// Re-queries the HealthKit heart-rate authorization status so the UI can
    /// explain a blank HR readout (denied vs. never asked). Safe to call
    /// repeatedly; does not itself trigger a permission prompt.
    func refreshHRAuthStatus(using authorizer: any HealthKitAuthorizing) async {
        hrAuthStatus = await authorizer.authorizationStatusForHeartRate()
    }

    func autoRackFromHardware() {
        stepLifecycle { lifecycle.autoRack() }
        restElapsed = 0
        stepLifecycle { lifecycle.restTick(elapsed: restElapsed) }
    }

#if DEBUG
    /// Preview/test-only: simulates the auto-spotter raising a Stage 1
    /// ("grinding") or Stage 2 ("RACK IT") escalation so `#Preview`s can show
    /// those states without live motion/HR input. Never wired to any
    /// production control — per ADR 0005 ("No mid-rep manual input"), a real
    /// lifter has no hands-free way to report a grind/pin mid-rep, so
    /// `SpotEngine`/`RepSegmenter` are the only real source of these events.
    func debugSimulateGrinding() {
        lifecycle.handle(spotEvent: spotEvent(kind: .grinding, confidence: 0.72, reason: .concentricTempo))
    }

    /// See `debugSimulateGrinding()` — same preview/test-only caveat.
    func debugSimulateRackIt() {
        lifecycle.handle(spotEvent: spotEvent(kind: .rackIt, confidence: 0.94, reason: .sustainedPin))
    }
#endif

    private func spotEvent(kind: SpotEventKind, confidence: Double, reason: SpotReason) -> SpotEvent {
        SpotEvent(
            kind: kind,
            timestamp: 0,
            repIndex: lifecycle.repCount,
            confidence: confidence,
            reason: reason
        )
    }

    /// Runs one pure `SetLifecycleController` mutation and emits the matching
    /// raw-set-capture marker(s) for whatever boundary it crossed (PRC-2). A
    /// single choke point keeps the capture marker timeline in lockstep with
    /// the state machine instead of sprinkling `emitCaptureMarker` through
    /// every call site. Each controller op crosses at most one state edge and
    /// bumps `repCount` by at most one, so the before/after diff is
    /// unambiguous: a rep increment to 1 is the rep-1 gate (setup over), any
    /// later increment is a normal rep. `alertStage`-only changes
    /// (`handle(spotEvent:)`) are intentionally NOT routed here — they aren't
    /// lifecycle boundaries.
    private func stepLifecycle(_ mutate: () -> Void) {
        let previousState = lifecycle.state
        let previousRepCount = lifecycle.repCount
        mutate()

        if lifecycle.repCount > previousRepCount {
            emitCaptureMarker(lifecycle.repCount == 1 ? .firstRep : .rep)
        }

        guard lifecycle.state != previousState else { return }
        switch lifecycle.state {
        case .settling: emitCaptureMarker(.settling)
        case .racked: emitCaptureMarker(.racked)
        case .resting: emitCaptureMarker(.restStarted)
        case .complete: emitCaptureMarker(.ended)
        case .idle, .repping: break
        }
    }

    /// Emits one capture marker on the seconds-since-arm clock — the same
    /// origin (`setStartedAt`) the motion/HR streams are aligned to. `nil`
    /// `setStartedAt` (a stray transition before arm) falls back to 0.
    private func emitCaptureMarker(_ kind: MarkerKind) {
        let secondsSinceArm = setStartedAt.map { max(Date().timeIntervalSince($0), 0) } ?? 0
        onCaptureMarker(kind, secondsSinceArm)
    }

    private var currentCalibration: CalibrationValues {
        switch calibrationState {
        case .fallback(let values), .ready(let values):
            values
        case .collecting(let candidate):
            candidate ?? CalibrationValues.fallback(for: lift)
        }
    }

}
