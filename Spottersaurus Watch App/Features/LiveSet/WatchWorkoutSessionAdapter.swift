import Foundation
import HealthKit
import SpottersaurusKit

@MainActor
final class WatchWorkoutSessionAdapter: NSObject, HKLiveWorkoutBuilderDelegate, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var onHeartRate: ((HRSample) -> Void)?

    var isRunning: Bool {
        session != nil
    }

    func start(onHeartRate: @escaping (HRSample) -> Void) async throws {
        guard session == nil else { return }

        self.onHeartRate = onHeartRate
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
        self.session = session
        self.builder = builder

        session.startActivity(with: now)
        try await builder.beginCollection(at: now)
    }

    func stop() async {
        guard let session, let builder else { return }

        let endedAt = Date()
        session.end()
        do {
            try await builder.endCollection(at: endedAt)
            _ = try await builder.finishWorkout()
        } catch {
            // The workout has already been ended; callers should not block UI
            // teardown on HealthKit persistence failures in this phase.
        }

        self.session = nil
        self.builder = nil
        self.startedAt = nil
        self.onHeartRate = nil
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
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}
