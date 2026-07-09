//
//  HistoryViewModelTests.swift
//  SpottersaurusTests
//
//  Covers the F1 hybrid conversion: HistoryViewModel owns derived (sorted)
//  session state via `update(with:)`, and its pure formatting helpers keep
//  their exact prior behavior.
//

import Foundation
import Testing
import SpottersaurusKit
@testable import Spottersaurus

@MainActor
struct HistoryViewModelTests {
    @Test func updateSortsSessionsNewestFirst() {
        let oldest = WorkoutSession(date: Date(timeIntervalSince1970: 1_000), source: .watch)
        let middle = WorkoutSession(date: Date(timeIntervalSince1970: 2_000), source: .phone)
        let newest = WorkoutSession(date: Date(timeIntervalSince1970: 3_000), source: .watch)

        let viewModel = HistoryViewModel()
        viewModel.update(with: [oldest, newest, middle])

        #expect(viewModel.sessions.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func updateReplacesPreviouslyDerivedSessions() {
        let first = WorkoutSession(date: Date(timeIntervalSince1970: 1_000), source: .watch)
        let second = WorkoutSession(date: Date(timeIntervalSince1970: 2_000), source: .watch)

        let viewModel = HistoryViewModel()
        viewModel.update(with: [first])
        #expect(viewModel.sessions.map(\.id) == [first.id])

        viewModel.update(with: [first, second])
        #expect(viewModel.sessions.map(\.id) == [second.id, first.id])
    }

    @Test func sessionTitleAndSubtitleMatchExpectedFormat() {
        let exercise = Exercise(name: "Bench Press", kind: .bench)
        let session = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000), source: .watch)
        let set = CompletedSet(exercise: exercise, weightKg: 100, repsPerformed: 5)
        session.appendCompletedSet(set)

        let viewModel = HistoryViewModel()

        #expect(viewModel.sessionTitle(session) == session.date.formatted(date: .abbreviated, time: .shortened))
        #expect(viewModel.sessionSubtitle(session) == "1 sets · 500 kg")
    }

    @Test func setTitleSubtitleAndVelocitySummaryMatchExpectedFormat() {
        let exercise = Exercise(name: "Bench Press", kind: .bench)
        let set = CompletedSet(
            exercise: exercise,
            weightKg: 100,
            repsPerformed: 5,
            avgConcentricVelocityMS: 0.512,
            peakConcentricVelocityMS: 0.734
        )

        let viewModel = HistoryViewModel()

        let load = set.weightKg.formatted(.number.precision(.fractionLength(1)))
        let e1RM = set.estimatedOneRepMaxKg.formatted(.number.precision(.fractionLength(1)))
        let average = set.avgConcentricVelocityMS.formatted(.number.precision(.fractionLength(2)))
        let peak = set.peakConcentricVelocityMS.formatted(.number.precision(.fractionLength(2)))

        #expect(viewModel.setTitle(set) == "Bench Press")
        #expect(viewModel.setSubtitle(set) == "\(load) kg × 5 · e1RM \(e1RM) kg")
        #expect(viewModel.velocitySummary(set) == "\(average) avg / \(peak) peak")
    }

    @Test func orderedSetsSortsByStartTime() {
        let exercise = Exercise(name: "Squat", kind: .squat)
        let session = WorkoutSession(date: Date(), source: .watch)
        let later = CompletedSet(exercise: exercise, weightKg: 120, repsPerformed: 3, startedAt: Date(timeIntervalSince1970: 200))
        let earlier = CompletedSet(exercise: exercise, weightKg: 120, repsPerformed: 3, startedAt: Date(timeIntervalSince1970: 100))
        session.appendCompletedSet(later)
        session.appendCompletedSet(earlier)

        let viewModel = HistoryViewModel()

        #expect(viewModel.orderedSets(in: session).map(\.id) == [earlier.id, later.id])
    }
}
