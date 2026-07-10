//
//  SpotEngine.swift
//  SpottersaurusKit
//
//  The conservative two-stage auto-spotter. Takes plain sample buffers in and
//  emits a stream of `SpotEvent`s out — no HealthKit, no CoreMotion, no
//  wall-clock. The Watch (Phase 4) feeds it live samples; here it is fully
//  deterministic and unit-tested headless on macOS.
//
//  Stage 1 (grinding nudge): a working rep's concentric runs long vs baseline
//  (> T1) or its mean velocity falls below the calibrated stall band.
//  Stage 2 (RACK IT): the grind persists — sustained near-zero velocity with no
//  lockout inside the max-concentric window (> T2 × baseline).
//
//  Wrist-tracked lifts (bench, deadlift) use the velocity path. Back-loaded
//  lifts (squat) disable velocity entirely and fall back to rep tempo plus an
//  injected HR-spike signal — there is no mid-rep manual input (ADR 0005): a
//  lifter's hands are locked on the bar for the entire working set, so a
//  "grind tap" gesture is physically impossible during a rep. Defaults are
//  conservative: prefer missing a borderline rep over startling a lifter
//  mid-clean-rep.
//

import Foundation

/// Tunable thresholds for the detection pipeline. Phase 9 ("sensitivity") can
/// swap these out; the defaults here are the conservative posture.
public struct SpotConfig: Sendable, Equatable {

    // MARK: Stage thresholds
    /// T1: concentric duration over `baseline × this` triggers Stage 1.
    public var grindDurationMultiplier: Double
    /// T2: concentric duration over `baseline × this` is the no-lockout window
    /// that, with a sustained stall, escalates to Stage 2.
    public var rackDurationMultiplier: Double
    /// Velocity at or below this (m/s) counts as "near zero" (a pinned bar).
    public var nearZeroVelocityMS: Double
    /// A near-zero run this long (s) inside the concentric is a sustained stall.
    public var sustainedStallSeconds: Double

    // MARK: Segmentation
    /// Velocity magnitude (m/s) above which the bar is "moving" for phase splits.
    public var moveThresholdMS: Double
    /// |accel| (m/s²) under which a sample is "quiet". A slow grind has low
    /// acceleration too, so quiet alone is not "racked" — see `minStillSeconds`.
    public var stillAccelThresholdMS2: Double
    /// A quiet stretch must last at least this long (s) to count as racked /
    /// paused. This distinguishes a genuine rest from the brief low-accel point
    /// at a rep's velocity peak (where the bar is moving fast, not still).
    public var minStillSeconds: Double
    /// Shortest accepted concentric (s); shorter excursions are noise.
    public var minPhaseSeconds: Double

    // MARK: Calibration
    /// Half-width of the velocity band as a fraction of mean warmup velocity.
    public var calibrationBandFraction: Double

    // MARK: Squat (tempo / HR) path
    /// HR rise (bpm) over the set baseline that counts as a strain spike.
    public var hrSpikeBPM: Double

    // MARK: Front end
    /// EMA time constant (s) for gravity removal.
    public var gravityTimeConstant: Double

    public init(
        grindDurationMultiplier: Double = 1.40,
        rackDurationMultiplier: Double = 2.0,
        nearZeroVelocityMS: Double = 0.08,
        sustainedStallSeconds: Double = 0.40,
        moveThresholdMS: Double = 0.10,
        stillAccelThresholdMS2: Double = 0.25,
        minStillSeconds: Double = 0.35,
        minPhaseSeconds: Double = 0.15,
        calibrationBandFraction: Double = 0.50,
        hrSpikeBPM: Double = 12.0,
        gravityTimeConstant: Double = 2.0
    ) {
        self.grindDurationMultiplier = grindDurationMultiplier
        self.rackDurationMultiplier = rackDurationMultiplier
        self.nearZeroVelocityMS = nearZeroVelocityMS
        self.sustainedStallSeconds = sustainedStallSeconds
        self.moveThresholdMS = moveThresholdMS
        self.stillAccelThresholdMS2 = stillAccelThresholdMS2
        self.minStillSeconds = minStillSeconds
        self.minPhaseSeconds = minPhaseSeconds
        self.calibrationBandFraction = calibrationBandFraction
        self.hrSpikeBPM = hrSpikeBPM
        self.gravityTimeConstant = gravityTimeConstant
    }

    /// The default conservative posture.
    public static let conservative = SpotConfig()
}

/// The escalation level of a spot event.
public enum SpotEventKind: String, Sendable, Codable, Equatable {
    /// Stage 1: soft "grinding" nudge.
    case grinding
    /// Stage 2: loud "RACK IT".
    case rackIt
    /// The flagged rep completed / was dismissed — clears the state.
    case resolved
}

/// Why an event fired — useful for review, tuning, and tests.
public enum SpotReason: String, Sendable, Codable, Equatable {
    case concentricTempo
    case velocityStall
    case sustainedPin
    case tempoCadence
    case hrSpike
    /// Not a live detection input (ADR 0005 — hands are locked on the bar
    /// mid-rep); reserved for a between-sets manual dismiss/tuning action.
    case manualTap
    case lockout
}

/// A single emitted spot event on the rep timeline.
public struct SpotEvent: Sendable, Equatable {
    public var kind: SpotEventKind
    /// Seconds since set-arm at which the condition was met.
    public var timestamp: TimeInterval
    /// Rep this event belongs to.
    public var repIndex: Int
    /// 0…1 confidence in the call.
    public var confidence: Double
    public var reason: SpotReason

    public init(kind: SpotEventKind, timestamp: TimeInterval, repIndex: Int, confidence: Double, reason: SpotReason) {
        self.kind = kind
        self.timestamp = timestamp
        self.repIndex = repIndex
        self.confidence = confidence
        self.reason = reason
    }
}

/// Per-rep detection output (maps onto the `RepMetric` model in Phase 4).
public struct RepResult: Sendable, Equatable {
    public var repIndex: Int
    public var concentricSeconds: Double
    public var meanVelocityMS: Double
    public var peakVelocityMS: Double
    public var displacementM: Double
    public var flaggedStall: Bool
    public var reachedRackIt: Bool

    public init(
        repIndex: Int,
        concentricSeconds: Double,
        meanVelocityMS: Double,
        peakVelocityMS: Double,
        displacementM: Double,
        flaggedStall: Bool,
        reachedRackIt: Bool
    ) {
        self.repIndex = repIndex
        self.concentricSeconds = concentricSeconds
        self.meanVelocityMS = meanVelocityMS
        self.peakVelocityMS = peakVelocityMS
        self.displacementM = displacementM
        self.flaggedStall = flaggedStall
        self.reachedRackIt = reachedRackIt
    }
}

/// The full result of analysing a set.
public struct SpotAnalysis: Sendable, Equatable {
    public var events: [SpotEvent]
    public var reps: [RepResult]
    /// Whether the VBT velocity path was used (false for back-loaded squats).
    public var usedVelocityPath: Bool

    public init(events: [SpotEvent], reps: [RepResult], usedVelocityPath: Bool) {
        self.events = events
        self.reps = reps
        self.usedVelocityPath = usedVelocityPath
    }
}

/// The conservative two-stage auto-spotter.
public struct SpotEngine: Sendable {
    public var lift: LiftKind
    public var calibration: CalibrationValues
    public var config: SpotConfig

    public init(lift: LiftKind, calibration: CalibrationValues, config: SpotConfig = .conservative) {
        self.lift = lift
        self.calibration = calibration
        self.config = config
    }

    /// Analyses a set: segments reps, runs the per-lift stage machine, and emits
    /// the event stream plus per-rep metrics.
    public func process(
        motion: [MotionSample],
        hr: [HRSample] = []
    ) -> SpotAnalysis {
        let linear = GravityRemover.axialAcceleration(motion, timeConstant: config.gravityTimeConstant)
        let phases = RepSegmenter(config: config).segment(linear, lift: lift)
        let usesVelocity = lift.usesVelocityPath

        var events: [SpotEvent] = []
        var reps: [RepResult] = []

        let firstRepStart = phases.first.map { $0.eccentricStart ?? $0.concentricStart } ?? 0
        let baseHR = baselineHR(hr, before: firstRepStart)
        let integrator = VelocityIntegrator(config: config)

        for phase in phases {
            let (evs, rep): ([SpotEvent], RepResult)
            if usesVelocity {
                (evs, rep) = analyzeVelocityPath(phase: phase, linear: linear, integrator: integrator)
            } else {
                (evs, rep) = analyzeTempoPath(phase: phase, hr: hr, baseHR: baseHR)
            }
            events.append(contentsOf: evs)
            reps.append(rep)
        }

        return SpotAnalysis(events: events, reps: reps, usedVelocityPath: usesVelocity)
    }

    // MARK: - Velocity path (bench / deadlift)

    private func analyzeVelocityPath(
        phase: RepPhase,
        linear: [LinearSample],
        integrator: VelocityIntegrator
    ) -> ([SpotEvent], RepResult) {
        let cv = integrator.integrate(linear, over: phase)
        let duration = phase.concentricSeconds
        let baseline = Swift.max(calibration.baselineConcentricSeconds, 1e-3)
        let ratio = duration / baseline
        let bandLower = calibration.velocityBandLowerMS

        // Stage 1: slow concentric OR mean velocity collapsed below the band.
        let slow = ratio > config.grindDurationMultiplier
        let weak = bandLower > 0 && cv.meanMS < bandLower
        let stage1 = slow || weak

        // Stage 2: a sustained near-zero stall AND no lockout within the window.
        let (stallSeconds, stallEnd) = longestNearZeroRun(cv.series)
        let stage2 = stage1
            && stallSeconds >= config.sustainedStallSeconds
            && duration > baseline * config.rackDurationMultiplier

        var events: [SpotEvent] = []
        if stage1 {
            let reason: SpotReason = weak ? .velocityStall : .concentricTempo
            events.append(
                SpotEvent(
                    kind: .grinding,
                    timestamp: stage1FireTime(phase: phase, baseline: baseline),
                    repIndex: phase.index,
                    confidence: grindConfidence(ratio: ratio, weak: weak),
                    reason: reason
                )
            )
            if stage2 {
                events.append(
                    SpotEvent(
                        kind: .rackIt,
                        timestamp: stallEnd ?? phase.concentricEnd,
                        repIndex: phase.index,
                        confidence: rackConfidence(stallSeconds: stallSeconds, ratio: ratio),
                        reason: .sustainedPin
                    )
                )
            } else {
                events.append(
                    SpotEvent(
                        kind: .resolved,
                        timestamp: phase.concentricEnd,
                        repIndex: phase.index,
                        confidence: 0.5,
                        reason: .lockout
                    )
                )
            }
        }

        let rep = RepResult(
            repIndex: phase.index,
            concentricSeconds: duration,
            meanVelocityMS: cv.meanMS,
            peakVelocityMS: cv.peakMS,
            displacementM: cv.displacementM,
            flaggedStall: stage1,
            reachedRackIt: stage2
        )
        return (events, rep)
    }

    // MARK: - Tempo / HR path (squat)

    private func analyzeTempoPath(
        phase: RepPhase,
        hr: [HRSample],
        baseHR: Double
    ) -> ([SpotEvent], RepResult) {
        let duration = phase.concentricSeconds
        let baseline = Swift.max(calibration.baselineConcentricSeconds, 1e-3)
        let ratio = duration / baseline

        let repStart = phase.eccentricStart ?? phase.concentricStart
        let repEnd = phase.concentricEnd
        let hrSpike = hrSpiked(hr, from: repStart, to: repEnd, baseHR: baseHR)

        // Stage 1: tempo drift past T1. HR alone is too noisy to fire on; it
        // only corroborates an escalation.
        let slow = ratio > config.grindDurationMultiplier
        let stage1 = slow
        // Stage 2: an extreme tempo blowout alone is unambiguous enough to
        // fire with no other signal; a merely moderate blowout (past T1 but
        // not yet past T2) needs a corroborating HR spike. No mid-rep manual
        // input exists (ADR 0005) — the lifter's hands are locked on the bar.
        let stage2 = stage1 && (ratio > config.rackDurationMultiplier || hrSpike)

        var events: [SpotEvent] = []
        if stage1 {
            events.append(
                SpotEvent(
                    kind: .grinding,
                    timestamp: stage1FireTime(phase: phase, baseline: baseline),
                    repIndex: phase.index,
                    confidence: grindConfidence(ratio: ratio, weak: false),
                    reason: .tempoCadence
                )
            )
            if stage2 {
                events.append(
                    SpotEvent(
                        kind: .rackIt,
                        timestamp: repEnd,
                        repIndex: phase.index,
                        confidence: rackConfidence(stallSeconds: config.sustainedStallSeconds, ratio: ratio),
                        // Tempo alone is the extreme, unambiguous case; if it
                        // wasn't extreme enough on its own, the HR spike is
                        // what tipped it.
                        reason: ratio > config.rackDurationMultiplier ? .sustainedPin : .hrSpike
                    )
                )
            } else {
                events.append(
                    SpotEvent(
                        kind: .resolved,
                        timestamp: repEnd,
                        repIndex: phase.index,
                        confidence: 0.5,
                        reason: .lockout
                    )
                )
            }
        }

        let rep = RepResult(
            repIndex: phase.index,
            concentricSeconds: duration,
            meanVelocityMS: 0,
            peakVelocityMS: 0,
            displacementM: 0,
            flaggedStall: stage1,
            reachedRackIt: stage2
        )
        return (events, rep)
    }

    // MARK: - Helpers

    /// Longest contiguous near-zero velocity run in the trace; returns its
    /// duration and the timestamp it ends at.
    private func longestNearZeroRun(_ series: [VelocitySample]) -> (Double, TimeInterval?) {
        guard !series.isEmpty else { return (0, nil) }
        let threshold = config.nearZeroVelocityMS
        var best = 0.0
        var bestEnd: TimeInterval? = nil
        var runStart: TimeInterval? = nil

        for s in series {
            if abs(s.velocityMS) < threshold {
                if runStart == nil { runStart = s.timestamp }
                let length = s.timestamp - (runStart ?? s.timestamp)
                if length > best { best = length; bestEnd = s.timestamp }
            } else {
                runStart = nil
            }
        }
        return (best, bestEnd)
    }

    /// When Stage 1 fires: the moment the concentric crosses the T1 duration, or
    /// the concentric end if it never gets that far in-window.
    private func stage1FireTime(phase: RepPhase, baseline: Double) -> TimeInterval {
        Swift.min(phase.concentricStart + baseline * config.grindDurationMultiplier, phase.concentricEnd)
    }

    private func grindConfidence(ratio: Double, weak: Bool) -> Double {
        var c = 0.5 + Swift.min(0.3, Swift.max(0, ratio - config.grindDurationMultiplier) * 0.5)
        if weak { c = Swift.max(c, 0.6) }
        return Swift.min(0.85, c)
    }

    private func rackConfidence(stallSeconds: Double, ratio: Double) -> Double {
        let c = 0.85 + Swift.min(0.14, Swift.max(0, stallSeconds - config.sustainedStallSeconds) * 0.1)
        return Swift.min(0.99, c)
    }

    /// Baseline HR = mean of samples before the first rep, falling back to the
    /// earliest sample.
    private func baselineHR(_ hr: [HRSample], before t: TimeInterval) -> Double {
        let pre = hr.filter { $0.timestamp < t }
        if !pre.isEmpty {
            return pre.reduce(0) { $0 + $1.beatsPerMinute } / Double(pre.count)
        }
        return hr.first?.beatsPerMinute ?? 0
    }

    private func hrSpiked(_ hr: [HRSample], from: TimeInterval, to: TimeInterval, baseHR: Double) -> Bool {
        guard baseHR > 0 else { return false }
        return hr.contains { $0.timestamp >= from && $0.timestamp <= to && $0.beatsPerMinute > baseHR + config.hrSpikeBPM }
    }
}
