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
    private var motionSamples: [MotionSample] = []
    private var heartRateSamples: [HRSample] = []
    private var processedRepCount = 0
    private let spotEngine: SpotEngine

    init(plannedSet: PlannedSetEnvelope, heartRate: Int = 132, velocityMS: Double = 0.42) {
        self.exerciseName = plannedSet.exerciseName
        self.lift = plannedSet.lift
        self.targetReps = plannedSet.targetReps
        self.weightKg = plannedSet.weightKg
        self.heartRate = heartRate
        self.velocityMS = velocityMS
        self.restElapsed = 0
        self.lifecycle = SetLifecycleController(restSeconds: TimeInterval(plannedSet.restSeconds))
        self.spotEngine = SpotEngine(
            lift: plannedSet.lift,
            calibration: CalibrationValues(
                lift: plannedSet.lift,
                baselineConcentricSeconds: 1.0,
                velocityBandLowerMS: plannedSet.lift.usesVelocityPath ? 0.18 : 0,
                velocityBandUpperMS: plannedSet.lift.usesVelocityPath ? 0.75 : 0,
                repCount: 0
            )
        )
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
        restElapsed = 0
        motionSamples = []
        heartRateSamples = []
        processedRepCount = 0
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

    private func trimSamples() {
        let motionFloor = (motionSamples.last?.timestamp ?? 0) - 30
        motionSamples.removeAll { $0.timestamp < motionFloor }

        let hrFloor = (heartRateSamples.last?.timestamp ?? 0) - 60
        heartRateSamples.removeAll { $0.timestamp < hrFloor }
    }
}
