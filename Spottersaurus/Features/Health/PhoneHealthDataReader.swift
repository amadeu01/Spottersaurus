//
//  PhoneHealthDataReader.swift
//  Spottersaurus
//
//  Concrete `HKHealthStore`-backed `HealthDataReading` conformer for the H2
//  Apple Health import. Lives here (not `SpottersaurusKit`) for the same
//  reason `PhoneHealthKitAuthorizer` does — HealthKit isn't importable from
//  the shared package, whose tests run headless on macOS. The HK-neutral
//  value types, query protocol, pure mapping (`HealthWorkoutMapper`), and
//  `HealthImporter` all live in `SpottersaurusKit/HealthKit/
//  HealthDataReading.swift` and are unit-tested there with a fake reader;
//  this type is exercised on-device / in the Simulator against real Health
//  data.
//
//  Queries `HKWorkout` filtered to `.functionalStrengthTraining` (newest
//  first) and the most recent `HKQuantityType(.bodyMass)` sample, converting
//  explicitly to kilograms. Read-only — no writes.
//

import Foundation
import HealthKit
import SpottersaurusKit

struct PhoneHealthDataReader: HealthDataReading {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func recentWorkouts(limit: Int) async throws -> [ImportedWorkout] {
        let predicate = HKSamplePredicate<HKWorkout>.workout(
            HKQuery.predicateForWorkouts(with: .functionalStrengthTraining)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        let workouts = try await descriptor.result(for: healthStore)
        return workouts.map(Self.mapWorkout)
    }

    func latestBodyWeight() async throws -> ImportedBodyWeight? {
        let predicate = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: HKQuantityType(.bodyMass)
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: healthStore)
        guard let sample = samples.first else { return nil }
        let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        return ImportedBodyWeight(date: sample.startDate, kilograms: kilograms)
    }

    private static func mapWorkout(_ workout: HKWorkout) -> ImportedWorkout {
        ImportedWorkout(
            healthKitUUID: workout.uuid,
            activity: mapActivity(workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            totalEnergyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
        )
    }

    private static func mapActivity(_ activityType: HKWorkoutActivityType) -> ImportedWorkoutActivity {
        switch activityType {
        case .functionalStrengthTraining:
            .functionalStrengthTraining
        case .traditionalStrengthTraining:
            .traditionalStrengthTraining
        case .running:
            .running
        default:
            .other
        }
    }
}
