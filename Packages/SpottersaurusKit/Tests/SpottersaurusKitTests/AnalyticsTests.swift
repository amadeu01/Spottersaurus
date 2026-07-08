//
//  AnalyticsTests.swift
//  SpottersaurusKitTests
//
//  TDD coverage for the pure, hardware-free Analytics layer: e1RM trends,
//  tonnage, VBT velocity-at-load scatter, and spotter-event frequency. All
//  inputs are plain `SetRecord` value types — no SwiftData container needed.
//

import XCTest
@testable import SpottersaurusKit

final class AnalyticsTests: XCTestCase {

    private func date(_ daysFromEpoch: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(daysFromEpoch) * 86_400)
    }

    // MARK: e1RM

    func testE1RMForKnownSet() {
        let set = SetRecord(lift: .bench, date: date(0), weightKg: 100, reps: 5)
        XCTAssertEqual(PerformanceAnalytics.e1RM(for: set), 116.7, accuracy: 0.05)
    }

    // MARK: e1RM trend

    func testE1RMTrendIsDateSortedAndFilteredByLift() {
        let sets = [
            SetRecord(lift: .bench, date: date(10), weightKg: 110, reps: 3),  // later, out of order
            SetRecord(lift: .squat, date: date(5), weightKg: 200, reps: 5),   // different lift, excluded
            SetRecord(lift: .bench, date: date(1), weightKg: 100, reps: 5),   // earliest
        ]

        let trend = PerformanceAnalytics.e1RMTrend(for: sets, lift: .bench)

        XCTAssertEqual(trend.map(\.date), [date(1), date(10)])
        XCTAssertEqual(trend.count, 2)
        XCTAssertEqual(trend[0].e1RMKg, 116.7, accuracy: 0.05)
        XCTAssertEqual(trend[1].e1RMKg, 121.0, accuracy: 0.05)
    }

    func testE1RMTrendEmptyInput() {
        let trend = PerformanceAnalytics.e1RMTrend(for: [SetRecord](), lift: .bench)
        XCTAssertTrue(trend.isEmpty)
    }

    // MARK: tonnage

    func testTonnageSumsWeightTimesReps() {
        let sets = [
            SetRecord(lift: .squat, date: date(0), weightKg: 100, reps: 5),  // 500
            SetRecord(lift: .squat, date: date(0), weightKg: 120, reps: 3),  // 360
        ]
        XCTAssertEqual(PerformanceAnalytics.tonnage(for: sets), 860, accuracy: 0.0001)
    }

    func testTonnageEmptyInputIsZero() {
        XCTAssertEqual(PerformanceAnalytics.tonnage(for: [SetRecord]()), 0, accuracy: 0.0001)
    }

    func testTonnageSeriesIsDateSortedAndFilteredByLift() {
        let sets = [
            SetRecord(lift: .deadlift, date: date(20), weightKg: 150, reps: 3),  // 450, later
            SetRecord(lift: .bench, date: date(5), weightKg: 80, reps: 5),       // different lift, excluded
            SetRecord(lift: .deadlift, date: date(2), weightKg: 140, reps: 5),   // 700, earliest
        ]

        let series = PerformanceAnalytics.tonnageSeries(for: sets, lift: .deadlift)

        XCTAssertEqual(series.map(\.date), [date(2), date(20)])
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].tonnageKg, 700, accuracy: 0.0001)
        XCTAssertEqual(series[1].tonnageKg, 450, accuracy: 0.0001)
    }

    func testTonnageSeriesEmptyInput() {
        let series = PerformanceAnalytics.tonnageSeries(for: [SetRecord](), lift: .deadlift)
        XCTAssertTrue(series.isEmpty)
    }

    // MARK: velocity-at-load (VBT scatter)

    func testVelocityLoadPointsFiltersByLiftAndDropsNilVelocity() {
        let sets = [
            SetRecord(lift: .bench, date: date(0), weightKg: 100, reps: 5, meanConcentricVelocityMS: 0.35),
            SetRecord(lift: .bench, date: date(1), weightKg: 110, reps: 3, meanConcentricVelocityMS: 0.22),
            SetRecord(lift: .squat, date: date(0), weightKg: 150, reps: 5, meanConcentricVelocityMS: 0.4), // different lift
            SetRecord(lift: .bench, date: date(2), weightKg: 120, reps: 1, meanConcentricVelocityMS: nil), // no VBT reading
        ]

        let points = PerformanceAnalytics.velocityLoadPoints(for: sets, lift: .bench)

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].weightKg, 100, accuracy: 0.0001)
        XCTAssertEqual(points[0].meanVelocityMS, 0.35, accuracy: 0.0001)
        XCTAssertEqual(points[1].weightKg, 110, accuracy: 0.0001)
        XCTAssertEqual(points[1].meanVelocityMS, 0.22, accuracy: 0.0001)
    }

    func testVelocityLoadPointsEmptyInput() {
        let points = PerformanceAnalytics.velocityLoadPoints(for: [SetRecord](), lift: .bench)
        XCTAssertTrue(points.isEmpty)
    }

    // MARK: spotter-event frequency

    func testSpotterEventFrequencyCountsGrindAndRackItPerLift() {
        let sets = [
            SetRecord(
                lift: .bench, date: date(0), weightKg: 100, reps: 5,
                spotterEvents: [
                    SpotterEvent(stage: .grind, timestamp: 1.0),
                    SpotterEvent(stage: .rackIt, timestamp: 2.0),
                ]
            ),
            SetRecord(
                lift: .bench, date: date(1), weightKg: 110, reps: 3,
                spotterEvents: [SpotterEvent(stage: .grind, timestamp: 0.5)]
            ),
            SetRecord(
                lift: .squat, date: date(0), weightKg: 150, reps: 5,
                spotterEvents: [SpotterEvent(stage: .rackIt, timestamp: 3.0)]
            ),
        ]

        let benchFrequency = PerformanceAnalytics.spotterEventFrequency(for: sets, lift: .bench)
        XCTAssertEqual(benchFrequency.grindCount, 2)
        XCTAssertEqual(benchFrequency.rackItCount, 1)

        let overallFrequency = PerformanceAnalytics.spotterEventFrequency(for: sets, lift: nil)
        XCTAssertEqual(overallFrequency.grindCount, 2)
        XCTAssertEqual(overallFrequency.rackItCount, 2)
    }

    func testSpotterEventFrequencyEmptyInput() {
        let frequency = PerformanceAnalytics.spotterEventFrequency(for: [SetRecord](), lift: nil)
        XCTAssertEqual(frequency.grindCount, 0)
        XCTAssertEqual(frequency.rackItCount, 0)
    }
}
