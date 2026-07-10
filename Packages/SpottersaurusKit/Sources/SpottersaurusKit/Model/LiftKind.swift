//
//  LiftKind.swift
//  SpottersaurusKit
//
//  The lift taxonomy and the bar-tracking profile that selects the
//  detection path. Wrist-tracked lifts (bench / deadlift) use wrist-motion
//  velocity; back-loaded lifts (squat) keep the wrist static so they fall
//  back to tempo + HR + manual grind tap. Pure value types — no SwiftData
//  here yet (schema lands in Phase 2).
//

import Foundation

/// How the bar moves relative to the wrist for a given lift. Selects the
/// detection path in `SpotEngine`.
public enum BarTracking: String, Codable, Sendable, CaseIterable {
    /// The wrist follows the bar through the concentric (bench, deadlift):
    /// wrist velocity is a usable proxy for bar velocity (VBT).
    case wristTracked
    /// The bar is loaded on the back and the wrist is roughly static (squat):
    /// the velocity path is disabled; rely on tempo + HR + manual grind tap.
    case backLoaded
}

/// The shape rep 1 of a set must show, keyed by where the bar starts at
/// arm (ADR 0006). Distinct from `BarTracking`: bench is wrist-tracked but
/// starts at the top like squat, while deadlift is wrist-tracked but starts
/// on the floor — so this needs the lift itself, not just the tracking mode.
public enum RepGateMode: String, Codable, Sendable, CaseIterable {
    /// Bar starts racked / held at the top (squat, bench): rep 1 must show
    /// an eccentric (down) immediately before its concentric (up). A lone
    /// upward excursion with no preceding descent — a walkout step, a
    /// re-rack adjustment — is not rep 1.
    case eccentricFirst
    /// Bar starts on the floor (deadlift): rep 1 is a concentric-from-rest,
    /// with no preceding eccentric.
    case concentricFirst
}

/// The set of lifts Spottersaurus understands. The three competition lifts
/// plus a catch-all for assistance work.
public enum LiftKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case squat
    case bench
    case deadlift
    case accessory

    public var id: String { rawValue }

    /// Human-facing label.
    public var displayName: String {
        switch self {
        case .squat: "Squat"
        case .bench: "Bench Press"
        case .deadlift: "Deadlift"
        case .accessory: "Accessory"
        }
    }

    /// The bar-tracking profile for this lift, which picks the detection path.
    /// Squat is back-loaded (wrist static); bench and deadlift are wrist-tracked.
    /// Accessory work defaults to wrist-tracked (most assistance lifts move the
    /// hands), and is treated conservatively by the engine regardless.
    public var barTracking: BarTracking {
        switch self {
        case .squat: .backLoaded
        case .bench, .deadlift, .accessory: .wristTracked
        }
    }

    /// Whether the wrist-velocity (VBT) path is available for this lift.
    public var usesVelocityPath: Bool {
        barTracking == .wristTracked
    }

    /// The rep-1 gate `RepSegmenter` applies after the post-arm settle
    /// (ADR 0006). Squat and bench start with the bar racked/held at the
    /// top; deadlift starts with the bar on the floor. Accessory work
    /// defaults to `.eccentricFirst` (most assistance lifts — presses,
    /// curls, rows off a rack — start from a held top position too).
    public var repGateMode: RepGateMode {
        switch self {
        case .deadlift: .concentricFirst
        case .squat, .bench, .accessory: .eccentricFirst
        }
    }
}
