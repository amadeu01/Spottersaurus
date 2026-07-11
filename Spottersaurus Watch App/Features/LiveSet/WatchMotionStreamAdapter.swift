import CoreMotion
import Foundation
import SpottersaurusKit

/// Streams fused device motion (ADR 0007): `CMBatchedSensorManager
/// .deviceMotionUpdates()` at 200 Hz is the primary source — CoreMotion's own
/// accelerometer+gyroscope sensor fusion, so gravity/rotation/attitude come
/// straight from the hardware instead of the raw-accelerometer EMA estimate.
/// If the batched stream fails to start (e.g. unsupported hardware or a
/// mid-session error), falls back to `CMMotionManager.startDeviceMotionUpdates`
/// — still fused device motion, just per-sample instead of batched — so the
/// fallback keeps gravity/attitude too rather than dropping to raw
/// accelerometer.
@MainActor
final class WatchMotionStreamAdapter {
    private let sensorManager = CMBatchedSensorManager()
    private let motionManager = CMMotionManager()
    private var motionTask: Task<Void, Never>?
    private var startedAt: TimeInterval?
    private var fallbackStartedAt: Date?

    var isRunning: Bool {
        motionTask != nil || motionManager.isDeviceMotionActive
    }

    func start(
        logger: any AppLogger = LoggerGroup.watch,
        onMotion: @escaping @MainActor ([DeviceMotionSample]) -> Void
    ) {
        guard !isRunning else { return }
        startedAt = nil
        fallbackStartedAt = nil
        logger.info(.motion, "starting batched device-motion stream")

        motionTask = Task { [sensorManager] in
            do {
                for try await batch in sensorManager.deviceMotionUpdates() {
                    if Task.isCancelled { break }
                    let samples = await MainActor.run {
                        self.makeSamples(from: batch)
                    }
                    await MainActor.run {
                        logger.debug(.motion, "batched device-motion samples=\(samples.count)")
                    }
                    await onMotion(samples)
                }
            } catch {
                await MainActor.run {
                    logger.warning(.motion, "batched device motion failed; starting fallback stream: \(error.localizedDescription)")
                    self.startFallback(logger: logger, onMotion: onMotion)
                }
            }
        }
    }

    func stop(logger: any AppLogger = LoggerGroup.watch) {
        if isRunning {
            logger.info(.motion, "stopping device-motion stream")
        }
        motionTask?.cancel()
        motionTask = nil
        motionManager.stopDeviceMotionUpdates()
        startedAt = nil
        fallbackStartedAt = nil
    }

    private func makeSamples(from batch: [CMDeviceMotion]) -> [DeviceMotionSample] {
        if startedAt == nil {
            startedAt = batch.first?.timestamp
        }
        let origin = startedAt ?? batch.first?.timestamp ?? 0
        return batch.map { sample in
            DeviceMotionSample(
                timestamp: max(sample.timestamp - origin, 0),
                userAccelerationG: Vector3(
                    x: sample.userAcceleration.x,
                    y: sample.userAcceleration.y,
                    z: sample.userAcceleration.z
                ),
                gravityG: Vector3(
                    x: sample.gravity.x,
                    y: sample.gravity.y,
                    z: sample.gravity.z
                ),
                rotationRateRadS: Vector3(
                    x: sample.rotationRate.x,
                    y: sample.rotationRate.y,
                    z: sample.rotationRate.z
                ),
                attitude: Quaternion(
                    w: sample.attitude.quaternion.w,
                    x: sample.attitude.quaternion.x,
                    y: sample.attitude.quaternion.y,
                    z: sample.attitude.quaternion.z
                )
            )
        }
    }

    /// `CMMotionManager.startDeviceMotionUpdates` — still fused device motion
    /// (gravity, rotation rate, attitude all come along), unlike a raw
    /// accelerometer fallback, at the cost of per-sample delivery instead of
    /// batching.
    private func startFallback(
        logger: any AppLogger,
        onMotion: @escaping @MainActor ([DeviceMotionSample]) -> Void
    ) {
        motionTask = nil
        guard motionManager.isDeviceMotionAvailable else {
            logger.error(.motion, "fallback device motion is unavailable")
            return
        }

        logger.info(.motion, "starting fallback device-motion stream")
        fallbackStartedAt = Date()
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let origin = self.fallbackStartedAt ?? Date()
            onMotion([
                DeviceMotionSample(
                    timestamp: max(Date().timeIntervalSince(origin), 0),
                    userAccelerationG: Vector3(
                        x: data.userAcceleration.x,
                        y: data.userAcceleration.y,
                        z: data.userAcceleration.z
                    ),
                    gravityG: Vector3(
                        x: data.gravity.x,
                        y: data.gravity.y,
                        z: data.gravity.z
                    ),
                    rotationRateRadS: Vector3(
                        x: data.rotationRate.x,
                        y: data.rotationRate.y,
                        z: data.rotationRate.z
                    ),
                    attitude: Quaternion(
                        w: data.attitude.quaternion.w,
                        x: data.attitude.quaternion.x,
                        y: data.attitude.quaternion.y,
                        z: data.attitude.quaternion.z
                    )
                )
            ])
        }
    }
}
