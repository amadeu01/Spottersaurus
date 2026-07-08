import CoreMotion
import Foundation
import SpottersaurusKit

@MainActor
final class WatchMotionStreamAdapter {
    private let sensorManager = CMBatchedSensorManager()
    private var motionTask: Task<Void, Never>?
    private var startedAt: TimeInterval?

    var isRunning: Bool {
        motionTask != nil
    }

    func start(onMotion: @escaping @MainActor ([MotionSample]) -> Void) {
        guard motionTask == nil else { return }
        startedAt = nil

        motionTask = Task { [sensorManager] in
            do {
                for try await batch in sensorManager.accelerometerUpdates() {
                    if Task.isCancelled { break }
                    let samples = await MainActor.run {
                        self.makeSamples(from: batch)
                    }
                    await onMotion(samples)
                }
            } catch {
                await MainActor.run {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        motionTask?.cancel()
        motionTask = nil
        startedAt = nil
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
}
