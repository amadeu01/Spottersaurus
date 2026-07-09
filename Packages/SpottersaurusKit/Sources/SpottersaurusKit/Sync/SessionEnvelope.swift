//
//  SessionEnvelope.swift
//  SpottersaurusKit
//
//  Codable DTOs for the Watch <-> iPhone link. Live in-set data and the
//  finished-session handoff travel as these envelopes over WatchConnectivity
//  (NOT CloudKit — too slow for live). Pure value types; the `WatchLink`
//  WCSession wrapper lands in Phase 6.
//

import Foundation

/// Codable projection of a single `RepMetric` — the detection engine's
/// per-rep output, mirrored for the Watch -> iPhone handoff.
public struct RepMetricEnvelope: Codable, Sendable, Equatable {
    /// Zero-based position of this rep within its set.
    public var repIndex: Int
    /// Concentric (lifting phase) duration, in seconds.
    public var concentricSeconds: Double
    /// Peak concentric velocity, in metres per second (VBT).
    public var peakVelocityMS: Double
    /// Mean concentric velocity, in metres per second (VBT).
    public var meanVelocityMS: Double
    /// Range-of-motion proxy (integrated displacement, normalised). Unitless.
    public var romProxy: Double
    /// Whether the engine flagged this rep as a stall / grind.
    public var flaggedStall: Bool

    public init(
        repIndex: Int,
        concentricSeconds: Double,
        peakVelocityMS: Double,
        meanVelocityMS: Double,
        romProxy: Double = 0,
        flaggedStall: Bool = false
    ) {
        self.repIndex = repIndex
        self.concentricSeconds = concentricSeconds
        self.peakVelocityMS = peakVelocityMS
        self.meanVelocityMS = meanVelocityMS
        self.romProxy = romProxy
        self.flaggedStall = flaggedStall
    }
}

/// Codable projection of a single `SpotEvent` emitted by `SpotEngine` — the
/// escalation stage, when it fired, which rep, and why. Reuses the engine's
/// own `SpotEventKind` / `SpotReason` enums (already `Codable`/`Sendable`)
/// rather than duplicating the vocabulary.
public struct SpotEventEnvelope: Codable, Sendable, Equatable {
    /// The two-stage escalation level (or `resolved`).
    public var stage: SpotEventKind
    /// Seconds since set-arm at which the condition was met.
    public var timestamp: TimeInterval
    /// Rep this event belongs to.
    public var repIndex: Int
    /// 0…1 confidence in the call.
    public var confidence: Double
    public var reason: SpotReason

    public init(stage: SpotEventKind, timestamp: TimeInterval, repIndex: Int, confidence: Double, reason: SpotReason) {
        self.stage = stage
        self.timestamp = timestamp
        self.repIndex = repIndex
        self.confidence = confidence
        self.reason = reason
    }
}

/// Codable projection of a `CalibrationValues` / `CalibrationProfile` — the
/// per-lift baseline (tempo + velocity band) captured during warmups, synced
/// so the Watch can seed the engine without recalibrating every session.
public struct CalibrationEnvelope: Codable, Sendable, Equatable {
    /// The lift this profile calibrates.
    public var lift: LiftKind
    /// Baseline concentric duration (seconds) from clean warmup reps.
    public var baselineConcentricSeconds: Double
    /// Lower bound of the expected concentric velocity band, m/s.
    public var velocityBandLowerMS: Double
    /// Upper bound of the expected concentric velocity band, m/s.
    public var velocityBandUpperMS: Double
    /// Number of warmup reps the baseline was derived from.
    public var repCount: Int
    /// When this baseline was captured (ISO-8601 when JSON-encoded).
    public var capturedAt: Date

    public init(
        lift: LiftKind,
        baselineConcentricSeconds: Double,
        velocityBandLowerMS: Double,
        velocityBandUpperMS: Double,
        repCount: Int = 0,
        capturedAt: Date = Date()
    ) {
        self.lift = lift
        self.baselineConcentricSeconds = baselineConcentricSeconds
        self.velocityBandLowerMS = velocityBandLowerMS
        self.velocityBandUpperMS = velocityBandUpperMS
        self.repCount = repCount
        self.capturedAt = capturedAt
    }
}

/// A single live in-set sample, streamed from the Watch to the iPhone while a
/// set is in progress (rep counter, current velocity, HR, elapsed time,
/// current Alert Stage, set N-of-M). Not persisted — purely a wire-format
/// tick for the live mirror UI. See ADR 0001 (`docs/adr/
/// 0001-live-session-surfaces-and-transport.md`): ticks carry running metrics
/// + the current Alert Stage, with `LiveSetLifecycleEnvelope` (below) driving
/// the hard set boundaries.
public struct LiveTickEnvelope: Codable, Sendable, Equatable {
    /// Reps completed so far in the in-progress set.
    public var repCount: Int
    /// Instantaneous concentric velocity, m/s (0 when between reps or on the
    /// tempo-only squat path).
    public var currentVelocityMS: Double
    /// Current heart rate, beats per minute.
    public var heartRateBPM: Double
    /// Seconds since the set was armed (monotonic), matching the sample clock.
    public var elapsedSeconds: TimeInterval
    /// Current spotter escalation level for this Live Set. Reuses
    /// `AlertStage` (`Session/SetLifecycleController.swift`) rather than a
    /// parallel wire-only enum, so the Watch's own lifecycle state is what
    /// travels over the wire, unmodified.
    public var alertStage: AlertStage
    /// Zero-based index of the current set within the Live Session (the "N"
    /// in "Set N of M").
    public var setIndex: Int
    /// Total number of sets in the Live Session (the "M" in "Set N of M").
    public var setCount: Int

    public init(
        repCount: Int,
        currentVelocityMS: Double,
        heartRateBPM: Double,
        elapsedSeconds: TimeInterval,
        alertStage: AlertStage = .none,
        setIndex: Int = 0,
        setCount: Int = 1
    ) {
        self.repCount = repCount
        self.currentVelocityMS = currentVelocityMS
        self.heartRateBPM = heartRateBPM
        self.elapsedSeconds = elapsedSeconds
        self.alertStage = alertStage
        self.setIndex = setIndex
        self.setCount = setCount
    }
}

/// An explicit Live Set Lifecycle Event marking the boundaries of a Live Set:
/// `armed` (set started; carries the concrete prescription + its position
/// within the Live Session) and `ended` (racked/completed). Distinct from
/// `LiveTickEnvelope`'s per-tick metric stream — these drive the iPhone
/// in-workout view, Live Activity, and Watch Always-On Display
/// deterministically, replacing a tick-recency heuristic (see ADR 0001 +
/// the "Live Set Lifecycle Event" glossary entry in `CONTEXT.md`).
public enum LiveSetLifecycleEnvelope: Codable, Sendable, Equatable {
    /// A new Live Set has started.
    case armed(
        lift: LiftKind,
        targetReps: Int,
        weightKg: Double,
        /// Zero-based position of this set within the Live Session.
        setIndex: Int,
        /// Total number of sets in the Live Session.
        setCount: Int
    )
    /// The Live Set (and, when it is the last set, the whole Live Session)
    /// has ended — racked or completed. Carries no payload; `SessionEnvelope`
    /// is the source of truth for the finished-set summary.
    case ended
}

/// A live control message from iPhone to Watch. Commands are intentionally
/// small and explicit: the Watch owns the workout state machine and maps each
/// command to the same action the wearer can tap locally.
public struct WatchCommandEnvelope: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case startWarmup
        case startWorkout
    }

    public var id: UUID
    public var kind: Kind
    public var issuedAt: Date

    public init(id: UUID = UUID(), kind: Kind, issuedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.issuedAt = issuedAt
    }
}

/// A single prescribed set sent from the iPhone planner to the Watch executor.
/// This is the concrete, Watch-ready version of `PlannedSet`: percentage loads
/// are resolved to kilograms before sending so the Watch does not need the
/// user's full max table to start a session.
public struct PlannedSetEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var lift: LiftKind
    public var exerciseName: String
    public var targetReps: Int
    public var weightKg: Double
    public var isAMRAP: Bool
    public var restSeconds: Int
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        lift: LiftKind,
        exerciseName: String,
        targetReps: Int,
        weightKg: Double,
        isAMRAP: Bool = false,
        restSeconds: Int = 180,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.lift = lift
        self.exerciseName = exerciseName
        self.targetReps = targetReps
        self.weightKg = weightKg
        self.isAMRAP = isAMRAP
        self.restSeconds = restSeconds
        self.sortIndex = sortIndex
    }
}

/// The iPhone planner's handoff to the Watch: one selected `ProgramDay` with
/// ordered, concrete planned sets.
public struct PlannedSessionEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var programName: String
    public var dayName: String
    public var createdAt: Date
    public var sets: [PlannedSetEnvelope]

    public init(
        id: UUID = UUID(),
        programName: String,
        dayName: String,
        createdAt: Date = Date(),
        sets: [PlannedSetEnvelope]
    ) {
        self.id = id
        self.programName = programName
        self.dayName = dayName
        self.createdAt = createdAt
        self.sets = sets
    }

    public var firstSet: PlannedSetEnvelope? {
        sets.sorted { $0.sortIndex < $1.sortIndex }.first
    }

    public static func make(
        program: Program,
        day: ProgramDay,
        maxes: [UserMaxes],
        createdAt: Date = Date()
    ) -> PlannedSessionEnvelope {
        PlannedSessionEnvelope(
            programName: program.name,
            dayName: day.name,
            createdAt: createdAt,
            sets: day.orderedSets.map { plannedSet in
                let exercise = plannedSet.exercise
                return PlannedSetEnvelope(
                    id: plannedSet.id,
                    lift: exercise?.kind ?? .accessory,
                    exerciseName: exercise?.name ?? "Lift",
                    targetReps: plannedSet.targetReps,
                    weightKg: Progression.resolvedWeightKg(for: plannedSet, maxes: maxes),
                    isAMRAP: plannedSet.isAMRAP,
                    restSeconds: plannedSet.restSeconds,
                    sortIndex: plannedSet.sortIndex
                )
            }
        )
    }
}

/// A finished-set summary handed from the Watch executor to the iPhone
/// reviewer: the load/reps, per-rep detail, any spotter escalations, and the
/// velocity summary — mirrors `CompletedSet` + its `RepMetric`s.
public struct CompletedSetEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var lift: LiftKind
    /// Wall-clock start of the set (ISO-8601 when JSON-encoded).
    public var startedAt: Date
    public var weightKg: Double
    public var repsCompleted: Int
    /// Per-rep detection output, sent alongside the summary.
    public var repMetrics: [RepMetricEnvelope]
    /// Spotter escalations that fired during the set.
    public var spotEvents: [SpotEventEnvelope]
    /// Average concentric velocity across the set, m/s (VBT).
    public var avgConcentricVelocityMS: Double
    /// Peak concentric velocity across the set, m/s (VBT).
    public var peakConcentricVelocityMS: Double

    public init(
        id: UUID = UUID(),
        lift: LiftKind,
        startedAt: Date,
        weightKg: Double,
        repsCompleted: Int,
        repMetrics: [RepMetricEnvelope] = [],
        spotEvents: [SpotEventEnvelope] = [],
        avgConcentricVelocityMS: Double = 0,
        peakConcentricVelocityMS: Double = 0
    ) {
        self.id = id
        self.lift = lift
        self.startedAt = startedAt
        self.weightKg = weightKg
        self.repsCompleted = repsCompleted
        self.repMetrics = repMetrics
        self.spotEvents = spotEvents
        self.avgConcentricVelocityMS = avgConcentricVelocityMS
        self.peakConcentricVelocityMS = peakConcentricVelocityMS
    }

    /// Estimated 1RM (kg) for this set via Epley — reuses the single-sourced
    /// `Epley` estimator from the model layer so the math never drifts.
    public var estimatedOneRepMaxKg: Double {
        Epley.e1RM(weightKg: weightKg, reps: repsCompleted)
    }
}

/// The top-level envelope for a finished session handed off to the phone.
public struct SessionEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Wall-clock session date (ISO-8601 when JSON-encoded).
    public var date: Date
    public var sets: [CompletedSetEnvelope]

    public init(id: UUID = UUID(), date: Date, sets: [CompletedSetEnvelope] = []) {
        self.id = id
        self.date = date
        self.sets = sets
    }

    /// Total tonnage (kg) across all sets — a tiny piece of real behavior so
    /// this type carries logic, not just storage.
    public var totalTonnageKg: Double {
        sets.reduce(0) { $0 + $1.weightKg * Double($1.repsCompleted) }
    }
}
