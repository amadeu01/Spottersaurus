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

    /// Whether wrist-velocity (VBT) *drives the alert trigger* for this lift —
    /// i.e. whether `SpotEngine` gates Stage 1/2 on velocity/stall (bench,
    /// deadlift) rather than tempo + HR (squat). Distinct from
    /// `computesVelocity`: see ADR 0009 — squat's wrist rides the bar and so
    /// yields a real, reportable velocity, but that number is not yet trusted
    /// to fire the safety-critical RACK IT trigger, pending validation against
    /// real captures.
    public var velocityDrivesAlerts: Bool {
        barTracking == .wristTracked
    }

    /// Whether `SpotEngine` computes and reports concentric velocity for this
    /// lift at all (independent of whether it drives alerts). True for every
    /// lift here: bench and deadlift are wrist-tracked in the ordinary VBT
    /// sense, and squat's hands are locked on the bar the whole rep, so wrist
    /// vertical velocity ≈ bar vertical velocity via the fused-gravity vertical
    /// projection (ADR 0009). Accessory follows its wrist-tracked profile.
    public var computesVelocity: Bool {
        switch self {
        case .squat, .bench, .deadlift: true
        case .accessory: barTracking == .wristTracked
        }
    }

    /// Deprecated alias of `velocityDrivesAlerts`, kept because it conflated
    /// "compute velocity" and "trigger on velocity" — see ADR 0009. Prefer
    /// `velocityDrivesAlerts` (trigger selection) or `computesVelocity`
    /// (whether the engine reports a velocity number at all).
    @available(*, deprecated, renamed: "velocityDrivesAlerts")
    public var usesVelocityPath: Bool { velocityDrivesAlerts }

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
