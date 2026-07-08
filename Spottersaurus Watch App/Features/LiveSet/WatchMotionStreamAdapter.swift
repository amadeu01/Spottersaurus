import CoreMotion
import Foundation
import SpottersaurusKit

@MainActor
final class WatchMotionStreamAdapter {
    private let sensorManager = CMBatchedSensorManager()
    private let motionManager = CMMotionManager()
    private var motionTask: Task<Void, Never>?
    private var startedAt: TimeInterval?
    private var fallbackStartedAt: Date?

    var isRunning: Bool {
        motionTask != nil || motionManager.isAccelerometerActive
    }

    func start(
        logger: any AppLogger = LoggerGroup.watch,
        onMotion: @escaping @MainActor ([MotionSample]) -> Void
    ) {
        guard !isRunning else { return }
        startedAt = nil
        fallbackStartedAt = nil
        logger.info(.motion, "starting batched accelerometer stream")

        motionTask = Task { [sensorManager] in
            do {
                for try await batch in sensorManager.accelerometerUpdates() {
                    if Task.isCancelled { break }
                    let samples = await MainActor.run {
                        self.makeSamples(from: batch)
                    }
                    await MainActor.run {
                        logger.debug(.motion, "batched accelerometer samples=\(samples.count)")
                    }
                    await onMotion(samples)
                }
            } catch {
                await MainActor.run {
                    logger.warning(.motion, "batched accelerometer failed; starting fallback stream: \(error.localizedDescription)")
                    self.startFallback(logger: logger, onMotion: onMotion)
                }
            }
        }
    }

    func stop(logger: any AppLogger = LoggerGroup.watch) {
        if isRunning {
            logger.info(.motion, "stopping accelerometer stream")
        }
        motionTask?.cancel()
        motionTask = nil
        motionManager.stopAccelerometerUpdates()
        startedAt = nil
        fallbackStartedAt = nil
    }

    private func makeSamples(from batch: [CMAccelerometerData]) -> [MotionSample] {
        if startedAt == nil {
            startedAt = batch.first?.timestamp
        }
        let origin = startedAt ?? batch.first?.timestamp ?? 0
        return batch.map { sample in
            MotionSample(
                timestamp: max(sample.timestamp - origin, 0),
                accelX: sample.acceleration.x,
                accelY: sample.acceleration.y,
                accelZ: sample.acceleration.z
            )
        }
    }

    private func startFallback(
        logger: any AppLogger,
        onMotion: @escaping @MainActor ([MotionSample]) -> Void
    ) {
        motionTask = nil
        guard motionManager.isAccelerometerAvailable else {
            logger.error(.motion, "fallback accelerometer is unavailable")
            return
        }

        logger.info(.motion, "starting fallback accelerometer stream")
        fallbackStartedAt = Date()
        motionManager.accelerometerUpdateInterval = 1.0 / 50.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let origin = self.fallbackStartedAt ?? Date()
            onMotion([
                MotionSample(
                    timestamp: max(Date().timeIntervalSince(origin), 0),
                    accelX: data.acceleration.x,
                    accelY: data.acceleration.y,
                    accelZ: data.acceleration.z
                )
            ])
        }
    }
}
