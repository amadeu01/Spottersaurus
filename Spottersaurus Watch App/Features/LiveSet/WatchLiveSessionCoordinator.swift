import Foundation
import SpottersaurusKit

@MainActor
final class WatchLiveSessionCoordinator {
    private let workoutAdapter = WatchWorkoutSessionAdapter()
    private let motionAdapter = WatchMotionStreamAdapter()
    private var tickGate = LiveTickGate()

    var isRunning: Bool {
        workoutAdapter.isRunning || motionAdapter.isRunning
    }

    func startMotion(
        viewModel: LiveSetViewModel,
        logger: any AppLogger = LoggerGroup.watch,
        onLiveTick: @escaping @MainActor (LiveTickEnvelope) -> Void = { _ in }
    ) {
        motionAdapter.start(logger: logger) { samples in
            viewModel.ingestMotionSamples(samples)
            let envelope = viewModel.liveTickEnvelope
            if self.tickGate.shouldSend(envelope) {
                onLiveTick(envelope)
            }
        }
    }

    func start(
        viewModel: LiveSetViewModel,
        logger: any AppLogger = LoggerGroup.watch,
        onLiveTick: @escaping @MainActor (LiveTickEnvelope) -> Void = { _ in }
    ) {
        logger.info(.liveSet, "starting live session coordinator")
        startMotion(viewModel: viewModel, logger: logger, onLiveTick: onLiveTick)

        Task {
            do {
                try await workoutAdapter.start(logger: logger) { sample in
                    viewModel.ingestHeartRate(sample)
                    let envelope = viewModel.liveTickEnvelope
                    if self.tickGate.shouldSend(envelope) {
                        onLiveTick(envelope)
                    }
                }
            } catch {
                logger.warning(.workout, "workout adapter start failed: \(error.localizedDescription)")
                // Simulator and devices without HealthKit authorization can
                // still exercise the live-set UI through manual controls.
            }
        }
    }

    func stop(logger: any AppLogger = LoggerGroup.watch) {
        logger.info(.liveSet, "stopping live session coordinator")
        motionAdapter.stop(logger: logger)
        tickGate.reset()
        Task {
            await workoutAdapter.stop()
        }
    }
}

@MainActor
private struct LiveTickGate {
    private var lastSentAt: Date?
    private var lastRepCount = -1
    private let minimumInterval: TimeInterval = 1

    mutating func shouldSend(_ envelope: LiveTickEnvelope, now: Date = Date()) -> Bool {
        guard envelope.repCount == lastRepCount, let lastSentAt else {
            markSent(envelope, now: now)
            return true
        }

        guard now.timeIntervalSince(lastSentAt) >= minimumInterval else {
            return false
        }

        markSent(envelope, now: now)
        return true
    }

    mutating func reset() {
        lastSentAt = nil
        lastRepCount = -1
    }

    private mutating func markSent(_ envelope: LiveTickEnvelope, now: Date) {
        lastSentAt = now
        lastRepCount = envelope.repCount
    }
}
