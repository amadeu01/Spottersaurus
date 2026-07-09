//
//  MaxesViewModelTests.swift
//  SpottersaurusTests
//
//  Covers the F3 hybrid conversion: MaxesViewModel owns derived
//  (competition-order) UserMaxes rows via `update(with:)`, and
//  `ensureCompetitionMaxesExist` keeps its exact prior insert behavior.
//

import Foundation
import Testing
import SwiftData
import SpottersaurusKit
@testable import Spottersaurus

@MainActor
struct MaxesViewModelTests {
    @Test func updateOrdersCompetitionMaxesSquatBenchDeadlift() {
        let bench = UserMaxes(lift: .bench, trainingMaxKg: 80, oneRepMaxKg: 100)
        let deadlift = UserMaxes(lift: .deadlift, trainingMaxKg: 150, oneRepMaxKg: 180)
        let squat = UserMaxes(lift: .squat, trainingMaxKg: 120, oneRepMaxKg: 140)

        let viewModel = MaxesViewModel()
        viewModel.update(with: [bench, deadlift, squat])

        #expect(viewModel.competitionMaxes.map(\.lift) == [.squat, .bench, .deadlift])
    }

    @Test func updateExcludesNonCompetitionLifts() {
        let squat = UserMaxes(lift: .squat, trainingMaxKg: 120, oneRepMaxKg: 140)
        let accessory = UserMaxes(lift: .accessory, trainingMaxKg: 20, oneRepMaxKg: 30)

        let viewModel = MaxesViewModel()
        viewModel.update(with: [squat, accessory])

        #expect(viewModel.competitionMaxes.map(\.lift) == [.squat])
    }

    @Test func updateOmitsMissingCompetitionLifts() {
        let bench = UserMaxes(lift: .bench, trainingMaxKg: 80, oneRepMaxKg: 100)

        let viewModel = MaxesViewModel()
        viewModel.update(with: [bench])

        #expect(viewModel.competitionMaxes.map(\.lift) == [.bench])
    }

    @Test func updateReplacesPreviouslyDerivedRows() {
        let squat = UserMaxes(lift: .squat, trainingMaxKg: 120, oneRepMaxKg: 140)
        let bench = UserMaxes(lift: .bench, trainingMaxKg: 80, oneRepMaxKg: 100)

        let viewModel = MaxesViewModel()
        viewModel.update(with: [squat])
        #expect(viewModel.competitionMaxes.map(\.lift) == [.squat])

        viewModel.update(with: [squat, bench])
        #expect(viewModel.competitionMaxes.map(\.lift) == [.squat, .bench])
    }

    @Test func ensureCompetitionMaxesExistInsertsOnlyMissingLifts() throws {
        let schema = Schema([UserMaxes.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)

        let existingSquat = UserMaxes(lift: .squat, trainingMaxKg: 120, oneRepMaxKg: 140)
        modelContext.insert(existingSquat)

        let viewModel = MaxesViewModel()
        viewModel.ensureCompetitionMaxesExist(in: modelContext, existingMaxes: [existingSquat])

        let inserted = try modelContext.fetch(FetchDescriptor<UserMaxes>())
        #expect(inserted.count == 3)
        #expect(Set(inserted.map(\.lift)) == Set(MaxesViewModel.competitionLifts))

        let squatRecord = inserted.first { $0.lift == .squat }
        #expect(squatRecord?.trainingMaxKg == 120)

        let benchRecord = inserted.first { $0.lift == .bench }
        #expect(benchRecord?.trainingMaxKg == 0)
        #expect(benchRecord?.oneRepMaxKg == 0)
    }
}
