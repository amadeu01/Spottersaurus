import Foundation
import SpottersaurusKit

@MainActor
final class WatchLiveSessionCoordinator {
    private let workoutAdapter = WatchWorkoutSessionAdapter()
    private let motionAdapter = WatchMotionStreamAdapter()

    var isRunning: Bool {
        workoutAdapter.isRunning || motionAdapter.isRunning
    }

    func startMotion(viewModel: LiveSetViewModel) {
        motionAdapter.start { samples in
            viewModel.ingestMotionSamples(samples)
        }
    }

    func start(viewModel: LiveSetViewModel) {
        startMotion(viewModel: viewModel)

        Task {
            do {
                try await workoutAdapter.start { sample in
                    viewModel.ingestHeartRate(sample)
                }
            } catch {
                // Simulator and devices without HealthKit authorization can
                // still exercise the live-set UI through manual controls.
            }
        }
    }

    func stop() {
        motionAdapter.stop()
        Task {
            await workoutAdapter.stop()
        }
    }
}
