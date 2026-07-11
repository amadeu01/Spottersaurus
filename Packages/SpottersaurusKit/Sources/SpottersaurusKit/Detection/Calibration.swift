//
//  Calibration.swift
//  SpottersaurusKit
//
//  Builds a per-lift baseline from warmup reps: the "normal" concentric tempo
//  and (for wrist-tracked lifts) the expected velocity band. The engine compares
//  working reps against this to decide what counts as a grind. Returns a plain
//  `CalibrationValues` struct — the app maps it onto the SwiftData
//  `CalibrationProfile` model; the engine itself stays SwiftData-free.
//

import Foundation

/// Plain, persistable baseline values produced from warmup reps. Mirrors the
/// fields of the `CalibrationProfile` model so the app can copy them across.
public struct CalibrationValues: Sendable, Equatable {
    public var lift: LiftKind
    /// Baseline concentric duration (s) — the tempo working reps are judged by.
    public var baselineConcentricSeconds: Double
    /// Lower edge of the expected concentric-velocity band, m/s (wrist-tracked
    /// lifts only; 0 for back-loaded lifts where the velocity path is disabled).
    public var velocityBandLowerMS: Double
    /// Upper edge of the expected concentric-velocity band, m/s.
    public var velocityBandUpperMS: Double
    /// Number of warmup reps the baseline was derived from.
    public var repCount: Int

    public init(
        lift: LiftKind,
        baselineConcentricSeconds: Double,
        velocityBandLowerMS: Double,
        velocityBandUpperMS: Double,
        repCount: Int
    ) {
        self.lift = lift
        self.baselineConcentricSeconds = baselineConcentricSeconds
        self.velocityBandLowerMS = velocityBandLowerMS
        self.velocityBandUpperMS = velocityBandUpperMS
        self.repCount = repCount
    }
}

/// Derives `CalibrationValues` from warmup motion.
public struct Calibration: Sendable {
    public var config: SpotConfig

    public init(config: SpotConfig = .conservative) {
        self.config = config
    }

    /// Calibrates a lift from a buffer of clean warmup reps.
    public func calibrate(lift: LiftKind, warmupMotion: [MotionSample]) -> CalibrationValues {
        let linear = GravityRemover.axialAcceleration(warmupMotion, timeConstant: config.gravityTimeConstant)
        let phases = RepSegmenter(config: config).segment(linear, lift: lift)
        return calibrate(lift: lift, linear: linear, phases: phases)
    }

    /// Calibrates from a pre-segmented warmup (lets callers reuse segmentation).
    public func calibrate(lift: LiftKind, linear: [LinearSample], phases: [RepPhase]) -> CalibrationValues {
        guard !phases.isEmpty else {
            return CalibrationValues(
                lift: lift,
                baselineConcentricSeconds: 0,
                velocityBandLowerMS: 0,
                velocityBandUpperMS: 0,
                repCount: 0
            )
        }

        let durations = phases.map(\.concentricSeconds)
        let baseline = durations.reduce(0, +) / Double(durations.count)

        var lower = 0.0
        var upper = 0.0
        // The velocity band only feeds the velocity-driven Stage 1 "weak"
        // gate (see SpotEngine.analyzeVelocityPath); squat computes velocity
        // now (ADR 0009) but does not trigger on it, so its band stays 0.
        if lift.velocityDrivesAlerts {
            let integrator = VelocityIntegrator(config: config)
            let means = phases.map { integrator.integrate(linear, over: $0).meanMS }
            let meanVel = means.reduce(0, +) / Double(means.count)
            let band = config.calibrationBandFraction
            lower = meanVel * (1 - band)
            upper = meanVel * (1 + band)
        }

        return CalibrationValues(
            lift: lift,
            baselineConcentricSeconds: baseline,
            velocityBandLowerMS: lower,
            velocityBandUpperMS: upper,
            repCount: phases.count
        )
    }
}
