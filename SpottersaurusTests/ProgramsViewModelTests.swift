//
//  ProgramsViewModelTests.swift
//  SpottersaurusTests
//
//  Covers the F4 hybrid conversion: ProgramsViewModel owns derived (sorted,
//  newest-first) Program state via `update(with:)`, and `deletePrograms`
//  operates on that owned order — same behavior the prior stateless
//  `sortedPrograms`/`deletePrograms(at:from:in:)` pair provided.
//

import Foundation
import Testing
import SwiftData
import SpottersaurusKit
@testable import Spottersaurus

@MainActor
struct ProgramsViewModelTests {
    @Test func updateSortsProgramsNewestFirst() {
        let oldest = Program(name: "Oldest", rule: .custom, createdAt: Date(timeIntervalSince1970: 1_000))
        let middle = Program(name: "Middle", rule: .linear, createdAt: Date(timeIntervalSince1970: 2_000))
        let newest = Program(name: "Newest", rule: .fivethreeone, createdAt: Date(timeIntervalSince1970: 3_000))

        let viewModel = ProgramsViewModel()
        viewModel.update(with: [oldest, newest, middle])

        #expect(viewModel.programs.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func updateReplacesPreviouslyDerivedPrograms() {
        let first = Program(name: "First", rule: .custom, createdAt: Date(timeIntervalSince1970: 1_000))
        let second = Program(name: "Second", rule: .custom, createdAt: Date(timeIntervalSince1970: 2_000))

        let viewModel = ProgramsViewModel()
        viewModel.update(with: [first])
        #expect(viewModel.programs.map(\.id) == [first.id])

        viewModel.update(with: [first, second])
        #expect(viewModel.programs.map(\.id) == [second.id, first.id])
    }

    @Test func deleteProgramsRemovesFromOwnedSortedOrder() throws {
        let schema = Schema([Program.self, ProgramDay.self, PlannedSet.self, Exercise.self, WorkoutSession.self, CompletedSet.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)

        let oldest = Program(name: "Oldest", rule: .custom, createdAt: Date(timeIntervalSince1970: 1_000))
        let newest = Program(name: "Newest", rule: .custom, createdAt: Date(timeIntervalSince1970: 2_000))
        modelContext.insert(oldest)
        modelContext.insert(newest)

        let viewModel = ProgramsViewModel()
        viewModel.update(with: [oldest, newest])
        #expect(viewModel.programs.map(\.id) == [newest.id, oldest.id])

        viewModel.deletePrograms(at: IndexSet(integer: 0), in: modelContext)

        let remaining = try modelContext.fetch(FetchDescriptor<Program>())
        #expect(remaining.map(\.id) == [oldest.id])
    }

    @Test func loadFiveThreeOneInsertsProgramWithFiveThreeOneRule() throws {
        let schema = Schema([Program.self, ProgramDay.self, PlannedSet.self, Exercise.self, WorkoutSession.self, CompletedSet.self, UserMaxes.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)

        let maxes = [
            UserMaxes(lift: .squat, trainingMaxKg: 120, oneRepMaxKg: 140),
            UserMaxes(lift: .bench, trainingMaxKg: 80, oneRepMaxKg: 100),
            UserMaxes(lift: .deadlift, trainingMaxKg: 150, oneRepMaxKg: 180)
        ]

        let viewModel = ProgramsViewModel()
        viewModel.loadFiveThreeOne(maxes: maxes, into: modelContext)

        let inserted = try modelContext.fetch(FetchDescriptor<Program>())
        #expect(inserted.count == 1)
        #expect(inserted.first?.rule == .fivethreeone)
    }
}
