import Foundation
import HealthKit
import SpottersaurusKit

@MainActor
final class WatchWorkoutSessionAdapter: NSObject, HKLiveWorkoutBuilderDelegate, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private let authorizer: any HealthKitAuthorizing
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var sessionState: HKWorkoutSessionState = .notStarted
    private var didBeginCollection = false
    private var onHeartRate: ((HRSample) -> Void)?
    private var logger: (any AppLogger)?

    init(authorizer: any HealthKitAuthorizing = HealthKitAuthorizer()) {
        self.authorizer = authorizer
        super.init()
    }

    var isRunning: Bool {
        session != nil
    }

    func start(
        logger: any AppLogger = LoggerGroup.watch,
        onHeartRate: @escaping (HRSample) -> Void
    ) async throws {
        guard session == nil else { return }

        self.logger = logger
        self.onHeartRate = onHeartRate

        // Ask-once, gated by the authorizer itself (HealthKitAuthorizer
        // persists the gate across launches) — safe to call unconditionally
        // on every arm. Must happen before startActivity/beginCollection so
        // HR flows and the finished workout is authorized to write back to
        // Apple Health. A denied or throwing request must never abort the
        // set: the manual/dev fallback (no HR, nothing written to Health)
        // keeps working either way.
        do {
            try await authorizer.requestAuthorization()
            let status = await authorizer.authorizationStatusForHeartRate()
            logger.info(.workout, "HealthKit authorization requested; heartRate status=\(status)")
        } catch {
            logger.warning(.workout, "HealthKit authorization request failed: \(error.localizedDescription); continuing without guaranteed HR/write access")
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        let now = Date()
        startedAt = now
        sessionState = .notStarted
        didBeginCollection = false
        self.session = session
        self.builder = builder

        logger.info(.workout, "starting HKWorkoutSession functionalStrengthTraining indoor")
        session.startActivity(with: now)
        try await builder.beginCollection(at: now)
        didBeginCollection = true
        logger.info(.workout, "HKLiveWorkoutBuilder collection started")
    }

    func stop() async {
        guard let session, let builder else { return }

        let endedAt = Date()
        guard didBeginCollection, sessionState == .running || sessionState == .paused else {
            logger?.info(.workout, "skipping HKWorkoutSession finish; state=\(sessionState.rawValue) didBeginCollection=\(didBeginCollection)")
            clearSession()
            return
        }

        logger?.info(.workout, "ending HKWorkoutSession state=\(sessionState.rawValue)")
        session.end()
        do {
            try await builder.endCollection(at: endedAt)
            _ = try await builder.finishWorkout()
            logger?.info(.workout, "HKLiveWorkoutBuilder finished workout")
        } catch {
            logger?.warning(.workout, "failed finishing HK workout: \(error.localizedDescription)")
            // The workout has already been ended; callers should not block UI
            // teardown on HealthKit persistence failures in this phase.
        }

        clearSession()
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        Task { @MainActor in
            guard let startedAt,
                  let statistics = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
                  let quantity = statistics.mostRecentQuantity()
            else { return }

            let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            logger?.debug(.workout, "heart rate sample bpm=\(bpm)")
            onHeartRate?(
                HRSample(
                    timestamp: max(Date().timeIntervalSince(startedAt), 0),
                    beatsPerMinute: bpm
                )
            )
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            sessionState = toState
            logger?.info(.workout, "HKWorkoutSession state \(fromState.rawValue)->\(toState.rawValue)")
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            logger?.error(.workout, "HKWorkoutSession failed: \(error.localizedDescription)")
        }
    }

    private func clearSession() {
        self.session = nil
        self.builder = nil
        self.startedAt = nil
        self.sessionState = .notStarted
        self.didBeginCollection = false
        self.onHeartRate = nil
        self.logger = nil
    }
}
