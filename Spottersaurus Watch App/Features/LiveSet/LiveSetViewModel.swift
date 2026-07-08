import Foundation
import Observation
import SpottersaurusKit

@Observable
final class LiveSetViewModel {
    let exerciseName: String
    let lift: LiftKind
    let targetReps: Int
    var weightKg: Double
    var heartRate: Int
    var velocityMS: Double
    var restElapsed: TimeInterval

    private var lifecycle: SetLifecycleController
    private var calibrationState: LiveSetCalibrationState
    private var warmupMotionSamples: [MotionSample] = []
    private var motionSamples: [MotionSample] = []
    private var heartRateSamples: [HRSample] = []
    private var processedRepCount = 0
    private var spotEngine: SpotEngine
    private let targetWarmupReps = 3

    init(plannedSet: PlannedSetEnvelope, heartRate: Int = 132, velocityMS: Double = 0.42) {
        let fallbackCalibration = CalibrationValues.fallback(for: plannedSet.lift)

        self.exerciseName = plannedSet.exerciseName
        self.lift = plannedSet.lift
        self.targetReps = plannedSet.targetReps
        self.weightKg = plannedSet.weightKg
        self.heartRate = heartRate
        self.velocityMS = velocityMS
        self.restElapsed = 0
        self.lifecycle = SetLifecycleController(restSeconds: TimeInterval(plannedSet.restSeconds))
        self.calibrationState = .fallback(fallbackCalibration)
        self.spotEngine = SpotEngine(lift: plannedSet.lift, calibration: fallbackCalibration)
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

    var statusText: String {
        switch lifecycle.alertStage {
        case .rackIt:
            "RACK IT"
        case .grinding:
            "GRINDING"
        case .none:
            switch lifecycle.state {
            case .idle: "READY"
            case .armed: "ARMED"
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

    func arm() {
        lifecycle.arm()
        calibrationState = .ready(currentCalibration)
        restElapsed = 0
        motionSamples = []
        heartRateSamples = []
        processedRepCount = 0
    }

    func startWarmupCalibration() {
        warmupMotionSamples = []
        calibrationState = .collecting(candidate: nil)
    }

    func finishWarmupCalibration() {
        let values = currentCalibration
        guard values.repCount > 0 else {
            calibrationState = .fallback(CalibrationValues.fallback(for: lift))
            spotEngine = SpotEngine(lift: lift, calibration: currentCalibration)
            return
        }

        calibrationState = .ready(values)
        spotEngine = SpotEngine(lift: lift, calibration: values)
    }

    func completeRep() {
        lifecycle.repCompleted()
        velocityMS = max(0.18, velocityMS - 0.03)
        heartRate += 3
    }

    func flagGrinding() {
        lifecycle.handle(spotEvent: spotEvent(kind: .grinding, confidence: 0.72, reason: .concentricTempo))
    }

    func rackIt() {
        lifecycle.handle(spotEvent: spotEvent(kind: .rackIt, confidence: 0.94, reason: .sustainedPin))
    }

    func rack() {
        if lifecycle.state == .armed {
            lifecycle.repCompleted()
        }
        lifecycle.autoRack()
        restElapsed = 0
        lifecycle.restTick(elapsed: restElapsed)
    }

    func finishRest() {
        restElapsed = lifecycle.restSeconds
        lifecycle.restTick(elapsed: restElapsed)
    }

    func resolveAlert() {
        lifecycle.handle(spotEvent: spotEvent(kind: .resolved, confidence: 1, reason: .manualTap))
    }

    func ingestMotionSamples(_ samples: [MotionSample]) {
        if calibrationState.isCollecting {
            warmupMotionSamples.append(contentsOf: samples)
            trimWarmupSamples()
            let candidate = Calibration().calibrate(lift: lift, warmupMotion: warmupMotionSamples)
            calibrationState = .collecting(candidate: candidate)
            return
        }

        guard lifecycle.state == .armed || lifecycle.state == .repping else { return }
        motionSamples.append(contentsOf: samples)
        trimSamples()

        let analysis = spotEngine.process(motion: motionSamples, hr: heartRateSamples)
        for rep in analysis.reps where rep.repIndex >= processedRepCount {
            lifecycle.repCompleted()
            processedRepCount = rep.repIndex + 1
            velocityMS = max(0, rep.meanVelocityMS)
        }
        for event in analysis.events {
            lifecycle.handle(spotEvent: event)
        }
    }

    func ingestHeartRate(_ sample: HRSample) {
        heartRateSamples.append(sample)
        heartRate = Int(sample.beatsPerMinute.rounded())
        trimSamples()
    }

    func autoRackFromHardware() {
        lifecycle.autoRack()
        restElapsed = 0
        lifecycle.restTick(elapsed: restElapsed)
    }

    private func spotEvent(kind: SpotEventKind, confidence: Double, reason: SpotReason) -> SpotEvent {
        SpotEvent(
            kind: kind,
            timestamp: 0,
            repIndex: lifecycle.repCount,
            confidence: confidence,
            reason: reason
        )
    }

    private var currentCalibration: CalibrationValues {
        switch calibrationState {
        case .fallback(let values), .ready(let values):
            values
        case .collecting(let candidate):
            candidate ?? CalibrationValues.fallback(for: lift)
        }
    }

    private func trimSamples() {
        let motionFloor = (motionSamples.last?.timestamp ?? 0) - 30
        motionSamples.removeAll { $0.timestamp < motionFloor }

        let hrFloor = (heartRateSamples.last?.timestamp ?? 0) - 60
        heartRateSamples.removeAll { $0.timestamp < hrFloor }
    }

    private func trimWarmupSamples() {
        let floor = (warmupMotionSamples.last?.timestamp ?? 0) - 45
        warmupMotionSamples.removeAll { $0.timestamp < floor }
    }
}
