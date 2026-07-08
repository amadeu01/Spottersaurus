//
//  PerformanceAnalytics.swift
//  SpottersaurusKit
//
//  Pure, hardware-free compute layer for the iPhone review screen: e1RM (and
//  its trend over time), session/per-lift tonnage, VBT velocity-at-load
//  scatter points, and spotter-event frequency. Plain functions over
//  `SetRecord` inputs — no SwiftUI, no SwiftData persistence, trivially
//  unit-testable with synthetic data.
//

import Foundation

/// Review-screen analytics computed from logged `SetRecord`s.
public enum PerformanceAnalytics {

    /// Estimated 1RM (kg) for a single set, via Epley.
    public static func e1RM(for set: SetRecord) -> Double {
        Epley.e1RM(weightKg: set.weightKg, reps: set.reps)
    }

    /// One point on an e1RM-over-time trend line.
    public struct TrendPoint: Sendable, Equatable {
        public var date: Date
        public var e1RMKg: Double

        public init(date: Date, e1RMKg: Double) {
            self.date = date
            self.e1RMKg = e1RMKg
        }
    }

    /// The e1RM trend for one lift, date-ascending, from an unordered/mixed-lift
    /// pool of sets.
    public static func e1RMTrend(for sets: [SetRecord], lift: LiftKind) -> [TrendPoint] {
        sets
            .filter { $0.lift == lift }
            .sorted { $0.date < $1.date }
            .map { TrendPoint(date: $0.date, e1RMKg: e1RM(for: $0)) }
    }

    /// Total tonnage (kg) across a pool of sets — Σ weight × reps.
    public static func tonnage(for sets: [SetRecord]) -> Double {
        sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    /// One point on a per-lift tonnage-over-time series (one set's tonnage).
    public struct TonnagePoint: Sendable, Equatable {
        public var date: Date
        public var tonnageKg: Double

        public init(date: Date, tonnageKg: Double) {
            self.date = date
            self.tonnageKg = tonnageKg
        }
    }

    /// Per-lift tonnage series, date-ascending, one point per set.
    public static func tonnageSeries(for sets: [SetRecord], lift: LiftKind) -> [TonnagePoint] {
        sets
            .filter { $0.lift == lift }
            .sorted { $0.date < $1.date }
            .map { TonnagePoint(date: $0.date, tonnageKg: $0.weightKg * Double($0.reps)) }
    }

    /// One point on a velocity-based-training (VBT) scatter: load vs. mean
    /// concentric velocity.
    public struct VelocityLoadPoint: Sendable, Equatable {
        public var weightKg: Double
        public var meanVelocityMS: Double

        public init(weightKg: Double, meanVelocityMS: Double) {
            self.weightKg = weightKg
            self.meanVelocityMS = meanVelocityMS
        }
    }

    /// Velocity-at-load points for one lift, in input order, dropping sets
    /// with no captured velocity reading (e.g. back-loaded squat).
    public static func velocityLoadPoints(for sets: [SetRecord], lift: LiftKind) -> [VelocityLoadPoint] {
        sets
            .filter { $0.lift == lift }
            .compactMap { set in
                guard let velocity = set.meanConcentricVelocityMS else { return nil }
                return VelocityLoadPoint(weightKg: set.weightKg, meanVelocityMS: velocity)
            }
    }

    /// Counts of spotter escalations by stage — how often the auto-spotter had
    /// to nudge ("grind") or shout ("RACK IT").
    public struct SpotterEventFrequency: Sendable, Equatable {
        public var grindCount: Int
        public var rackItCount: Int

        public init(grindCount: Int, rackItCount: Int) {
            self.grindCount = grindCount
            self.rackItCount = rackItCount
        }
    }

    /// Spotter-event frequency across a pool of sets, optionally scoped to one
    /// lift. `lift: nil` aggregates across all lifts.
    public static func spotterEventFrequency(for sets: [SetRecord], lift: LiftKind?) -> SpotterEventFrequency {
        let scoped = lift.map { target in sets.filter { $0.lift == target } } ?? sets
        let events = scoped.flatMap(\.spotterEvents)
        let grindCount = events.filter { $0.stage == .grind }.count
        let rackItCount = events.filter { $0.stage == .rackIt }.count
        return SpotterEventFrequency(grindCount: grindCount, rackItCount: rackItCount)
    }
}
