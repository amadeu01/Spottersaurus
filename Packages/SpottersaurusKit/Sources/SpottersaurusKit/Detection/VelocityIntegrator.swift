//
//  VelocityIntegrator.swift
//  SpottersaurusKit
//
//  Estimates concentric bar velocity (VBT) by integrating bar-axis acceleration
//  over a detected concentric window. Drift is handled by a boundary
//  zero-velocity assumption: a powerlifting concentric starts and ends near rest
//  (bottom sticking point → lockout / settle), so the raw integral is detrended
//  to force both endpoints to zero — a high-pass that removes the linear drift
//  an accelerometer bias would otherwise accumulate. Pure math, no hardware.
//

import Foundation

/// One point on a recovered concentric velocity trace.
public struct VelocitySample: Sendable, Equatable, Timestamped {
    public var timestamp: TimeInterval
    public var velocityMS: Double

    public init(timestamp: TimeInterval, velocityMS: Double) {
        self.timestamp = timestamp
        self.velocityMS = velocityMS
    }
}

/// Recovered velocity summary for a single concentric.
public struct ConcentricVelocity: Sendable, Equatable {
    /// Mean concentric velocity, m/s (the headline VBT number).
    public var meanMS: Double
    /// Peak concentric velocity, m/s.
    public var peakMS: Double
    /// Net displacement over the concentric, m — a range-of-motion proxy.
    public var displacementM: Double
    /// The full drift-corrected velocity trace.
    public var series: [VelocitySample]

    public init(meanMS: Double, peakMS: Double, displacementM: Double, series: [VelocitySample]) {
        self.meanMS = meanMS
        self.peakMS = peakMS
        self.displacementM = displacementM
        self.series = series
    }

    public static let zero = ConcentricVelocity(meanMS: 0, peakMS: 0, displacementM: 0, series: [])
}

/// Integrates acceleration into a drift-corrected concentric velocity estimate.
public struct VelocityIntegrator: Sendable {
    public var config: SpotConfig

    public init(config: SpotConfig = .conservative) {
        self.config = config
    }

    /// Integrates the bar-axis acceleration falling inside `phase`'s concentric.
    public func integrate(_ linear: [LinearSample], over phase: RepPhase) -> ConcentricVelocity {
        let eps = 1e-6
        let window = linear.filter {
            $0.timestamp >= phase.concentricStart - eps && $0.timestamp <= phase.concentricEnd + eps
        }
        return integrate(window)
    }

    /// Integrates a contiguous bar-axis acceleration window into velocity.
    public func integrate(_ window: [LinearSample]) -> ConcentricVelocity {
        guard window.count >= 2 else { return .zero }
        let eps = 1e-6

        // Raw trapezoidal integral, starting from rest.
        var raw = [Double](repeating: 0, count: window.count)
        for i in 1..<window.count {
            let dt = window[i].timestamp - window[i - 1].timestamp
            raw[i] = raw[i - 1] + 0.5 * (window[i].axialMS2 + window[i - 1].axialMS2) * dt
        }

        // Detrend: subtract the straight line that pins both endpoints to zero
        // (ZUPT at the phase boundaries). This is the drift-handling step.
        let t0 = window.first!.timestamp
        let t1 = window.last!.timestamp
        let span = Swift.max(t1 - t0, eps)
        let endVel = raw.last!

        var series: [VelocitySample] = []
        series.reserveCapacity(window.count)
        var corrected = [Double](repeating: 0, count: window.count)
        for i in 0..<window.count {
            let c = raw[i] - endVel * (window[i].timestamp - t0) / span
            corrected[i] = c
            series.append(VelocitySample(timestamp: window[i].timestamp, velocityMS: c))
        }

        // Mean over the trace; peak of the (positive) concentric motion.
        let mean = corrected.reduce(0, +) / Double(corrected.count)
        let peak = corrected.max() ?? 0

        // Net displacement (∫v dt) as a ROM proxy.
        var disp = 0.0
        for i in 1..<window.count {
            let dt = window[i].timestamp - window[i - 1].timestamp
            disp += 0.5 * (corrected[i] + corrected[i - 1]) * dt
        }

        return ConcentricVelocity(meanMS: mean, peakMS: peak, displacementM: disp, series: series)
    }
}
