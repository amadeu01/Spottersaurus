//
//  ConnectionStatus.swift
//  SpottersaurusKit
//
//  Pure, hardware-free projection of `WCSession` state into a single
//  human-facing status. Lives in the shared package (rather than the iOS
//  app target) purely so `resolve` is unit-testable without importing
//  WatchConnectivity or running on a device/simulator pair.
//

import Foundation

/// Reachability/pairing status of the paired Apple Watch, as derived from a
/// `WCSession` snapshot. Ordered roughly worst -> best.
public enum ConnectionStatus: String, Sendable, Equatable, CaseIterable {
    /// `WCSession` hasn't finished activating yet (or activation reported
    /// `.notActivated` / `.inactive`). Transient — expect a follow-up
    /// delegate callback shortly after app launch.
    case inactive
    /// No Apple Watch is paired with this iPhone at all.
    case notPaired
    /// A Watch is paired, but the Spottersaurus Watch app isn't installed.
    case appNotInstalled
    /// Watch app is installed and paired, but not currently reachable
    /// (out of BT/WiFi range, Watch app not foregrounded, etc). Queued
    /// application-context/userInfo transfers still work in this state.
    case pairedNotReachable
    /// Fully activated, paired, installed, and reachable — live
    /// `sendMessage`/`sendMessageData` will succeed.
    case connected

    /// Mirrors `WCSessionActivationState` raw values so this package doesn't
    /// need to import WatchConnectivity:
    ///   - `0` = `.notActivated`
    ///   - `1` = `.inactive`
    ///   - `2` = `.activated`
    /// Any other value is treated as not-activated (fails safe to `.inactive`).
    public static let activatedRawValue = 2

    /// Pure reducer mapping a `WCSession` state snapshot to a `ConnectionStatus`.
    ///
    /// Precedence (most authoritative flag first): not-paired always wins,
    /// regardless of the other flags (an unpaired session can still report
    /// stale `isWatchAppInstalled`/`isReachable` values); then activation;
    /// then app-installed; then reachability.
    public static func resolve(
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isReachable: Bool,
        activationState: Int
    ) -> ConnectionStatus {
        guard isPaired else { return .notPaired }
        guard activationState == activatedRawValue else { return .inactive }
        guard isWatchAppInstalled else { return .appNotInstalled }
        guard isReachable else { return .pairedNotReachable }
        return .connected
    }
}
