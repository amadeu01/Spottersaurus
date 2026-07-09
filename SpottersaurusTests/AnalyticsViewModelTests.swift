//
//  AnalyticsViewModelTests.swift
//  SpottersaurusTests
//
//  Covers the F2 hybrid conversion: AnalyticsViewModel owns derived analytics
//  input (SetRecords) via `update(with:)`, and the pure PerformanceAnalytics
//  layer computes identical series from that owned state as it did from the
//  view's ad-hoc `records` before the conversion.
//

import Foundation
import Testing
import SpottersaurusKit
@testable import Spottersaurus

@MainActor
struct AnalyticsViewModelTests {
    @Test func updatePopulatesRecordsFromSessions() {
        let exercise = Exercise(name: "Bench Press", kind: .bench)
        let session = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000), source: .watch)
        let set = CompletedSet(
            exercise: exercise,
            weightKg: 100,
            repsPerformed: 5,
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            avgConcentricVelocityMS: 0.5
        )
        session.appendCompletedSet(set)

        let viewModel = AnalyticsViewModel()
        #expect(viewModel.records.isEmpty)

        viewModel.update(with: [session])

        #expect(viewModel.records.count == 1)
        #expect(viewModel.records.first?.lift == .bench)
        #expect(viewModel.records.first?.weightKg == 100)
        #expect(viewModel.records.first?.reps == 5)
    }

    @Test func updateReplacesPreviouslyDerivedRecords() {
        let exercise = Exercise(name: "Squat", kind: .squat)
        let first = WorkoutSession(date: Date(timeIntervalSince1970: 1_000), source: .watch)
        first.appendCompletedSet(CompletedSet(exercise: exercise, weightKg: 100, repsPerformed: 5))

        let second = WorkoutSession(date: Date(timeIntervalSince1970: 2_000), source: .watch)
        second.appendCompletedSet(CompletedSet(exercise: exercise, weightKg: 110, repsPerformed: 3))

        let viewModel = AnalyticsViewModel()
        viewModel.update(with: [first])
        #expect(viewModel.records.count == 1)

        viewModel.update(with: [first, second])
        #expect(viewModel.records.count == 2)
    }

    @Test func e1RMTrendMatchesPerformanceAnalyticsForOwnedRecords() {
        let exercise = Exercise(name: "Bench Press", kind: .bench)
        let session = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000), source: .watch)
        let earlier = CompletedSet(
            exercise: exercise,
            weightKg: 100,
            repsPerformed: 5,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let later = CompletedSet(
            exercise: exercise,
            weightKg: 105,
            repsPerformed: 3,
            startedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )
        session.appendCompletedSet(later)
        session.appendCompletedSet(earlier)

        let viewModel = AnalyticsViewModel()
        viewModel.update(with: [session])

        let expected = PerformanceAnalytics.e1RMTrend(for: viewModel.records, lift: .bench)
        #expect(viewModel.e1RMTrend(lift: .bench) == expected)
        #expect(expected.map(\.date) == [earlier.startedAt, later.startedAt])
    }

    @Test func totalTonnageAndBestE1RMAreLocaleAgnostic() {
        let exercise = Exercise(name: "Deadlift", kind: .deadlift)
        let session = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000), source: .watch)
        let set = CompletedSet(exercise: exercise, weightKg: 150, repsPerformed: 5)
        session.appendCompletedSet(set)

        let viewModel = AnalyticsViewModel()
        viewModel.update(with: [session])

        let expectedTonnage = PerformanceAnalytics.tonnage(for: viewModel.records)
            .formatted(.number.precision(.fractionLength(0)))
        let expectedBest = PerformanceAnalytics.e1RM(for: viewModel.records[0])
            .formatted(.number.precision(.fractionLength(1)))

        #expect(viewModel.totalTonnage() == expectedTonnage)
        #expect(viewModel.bestEstimatedOneRepMax(lift: .deadlift) == expectedBest)
    }
}
