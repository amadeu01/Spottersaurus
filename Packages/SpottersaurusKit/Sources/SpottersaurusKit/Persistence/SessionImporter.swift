//
//  SessionImporter.swift
//  SpottersaurusKit
//
//  Maps a received `SessionEnvelope` (the Watch -> iPhone finished-session
//  handoff DTO) onto the shared SwiftData schema and inserts it into a given
//  `ModelContext`. Pure mapping: no SwiftUI, no WatchConnectivity, no
//  HealthKit — the caller owns transport and context lifecycle.
//

import Foundation
import SwiftData

/// Imports finished-session envelopes into SwiftData, upserting by envelope id
/// so a re-delivered envelope (WatchConnectivity has no exactly-once guarantee)
/// never produces duplicate history.
@MainActor
public enum SessionImporter {

    /// Imports `envelope` into `context`, creating a `WorkoutSession` (with its
    /// `CompletedSet`s and ordered `RepMetric`s) or, if a session with the same
    /// `id` already exists, replacing its sets in place.
    ///
    /// - Returns: the inserted/updated `WorkoutSession`.
    @discardableResult
    public static func importSession(_ envelope: SessionEnvelope, into context: ModelContext) throws -> WorkoutSession {
        let envelopeID = envelope.id
        let existing = try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == envelopeID })
        ).first

        let session: WorkoutSession
        if let existing {
            session = existing
            session.date = envelope.date
            // Upsert by clearing the prior sets (cascade removes their rep
            // metrics too) and rebuilding from the re-delivered envelope, so a
            // retried/duplicate handoff never produces duplicate history.
            for set in session.completedSets {
                context.delete(set)
            }
            session.completedSets = []
        } else {
            session = WorkoutSession(date: envelope.date, source: .watch, id: envelopeID)
            context.insert(session)
        }

        session.completedSets = envelope.sets.map { makeCompletedSet(from: $0, context: context) }

        try context.save()
        return session
    }

    private static func makeCompletedSet(from envelope: CompletedSetEnvelope, context: ModelContext) -> CompletedSet {
        let set = CompletedSet(
            exercise: findOrCreateExercise(for: envelope.lift, context: context),
            weightKg: envelope.weightKg,
            repsPerformed: envelope.repsCompleted,
            startedAt: envelope.startedAt,
            avgConcentricVelocityMS: envelope.avgConcentricVelocityMS,
            peakConcentricVelocityMS: envelope.peakConcentricVelocityMS,
            id: envelope.id
        )
        set.repMetrics = envelope.repMetrics.map(makeRepMetric)
        set.spotterEvents = envelope.spotEvents.compactMap(makeSpotterEvent)
        return set
    }

    /// Maps a wire `SpotEventEnvelope` to the persisted `SpotterEvent`.
    /// `.resolved` is a Watch-side state-clear with no escalation stage of its
    /// own (`SpotterEvent.Stage` only models `grind` / `rackIt`) — it carries no
    /// history-worthy signal, so it is dropped rather than force-mapped.
    private static func makeSpotterEvent(from envelope: SpotEventEnvelope) -> SpotterEvent? {
        let stage: SpotterEvent.Stage
        switch envelope.stage {
        case .grinding: stage = .grind
        case .rackIt: stage = .rackIt
        case .resolved: return nil
        }
        return SpotterEvent(stage: stage, timestamp: envelope.timestamp, repIndex: envelope.repIndex)
    }

    private static func makeRepMetric(from envelope: RepMetricEnvelope) -> RepMetric {
        RepMetric(
            repIndex: envelope.repIndex,
            concentricSeconds: envelope.concentricSeconds,
            peakVelocityMS: envelope.peakVelocityMS,
            meanVelocityMS: envelope.meanVelocityMS,
            romProxy: envelope.romProxy,
            flaggedStall: envelope.flaggedStall
        )
    }

    /// Finds an existing `Exercise` whose kind matches the envelope's lift, or
    /// creates (and inserts) one. The envelope only carries the lift taxonomy,
    /// not a specific named exercise, so lift kind is the best available join
    /// key for this landing step.
    private static func findOrCreateExercise(for lift: LiftKind, context: ModelContext) -> Exercise {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.kind == lift })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let exercise = Exercise(name: lift.displayName, kind: lift)
        context.insert(exercise)
        return exercise
    }
}
