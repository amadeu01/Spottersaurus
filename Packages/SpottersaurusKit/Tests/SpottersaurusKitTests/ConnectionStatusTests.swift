//
//  ConnectionStatusTests.swift
//  SpottersaurusKitTests
//
//  Table-tests for the pure `ConnectionStatus.resolve` reducer that maps a
//  WCSession state snapshot to a `ConnectionStatus`. No WatchConnectivity
//  import needed — activation state is mirrored as a plain Int so this stays
//  unit-testable off-device.
//

import Testing
@testable import SpottersaurusKit

struct ConnectionStatusTests {

    // MARK: - Not paired dominates every other flag

    @Test func notPairedWinsRegardlessOfOtherFlags() {
        #expect(
            ConnectionStatus.resolve(
                isPaired: false,
                isWatchAppInstalled: false,
                isReachable: false,
                activationState: 0
            ) == .notPaired
        )
        #expect(
            ConnectionStatus.resolve(
                isPaired: false,
                isWatchAppInstalled: true,
                isReachable: true,
                activationState: 2
            ) == .notPaired
        )
    }

    // MARK: - Pre-activation

    @Test func notActivatedYieldsInactiveWhenPaired() {
        #expect(
            ConnectionStatus.resolve(
                isPaired: true,
                isWatchAppInstalled: true,
                isReachable: false,
                activationState: 0
            ) == .inactive
        )
    }

    @Test func inactiveActivationStateYieldsInactiveWhenPaired() {
        #expect(
            ConnectionStatus.resolve(
                isPaired: true,
                isWatchAppInstalled: true,
                isReachable: false,
                activationState: 1
            ) == .inactive
        )
    }

    // MARK: - App not installed

    @Test func pairedButAppNotInstalled() {
        #expect(
            ConnectionStatus.resolve(
                isPaired: true,
                isWatchAppInstalled: false,
                isReachable: false,
                activationState: 2
            ) == .appNotInstalled
        )
    }

    // MARK: - Paired + installed, not reachable

    @Test func pairedInstalledNotReachable() {
        #expect(
            ConnectionStatus.resolve(
                isPaired: true,
                isWatchAppInstalled: true,
                isReachable: false,
                activationState: 2
            ) == .pairedNotReachable
        )
    }

    // MARK: - Fully connected

    @Test func pairedInstalledReachableActivatedIsConnected() {
        #expect(
            ConnectionStatus.resolve(
                isPaired: true,
                isWatchAppInstalled: true,
                isReachable: true,
                activationState: 2
            ) == .connected
        )
    }

    // Reachability without full activation shouldn't report `.connected` —
    // activation is the source of truth for "the session is live."
    @Test func reachableButNotActivatedIsNotConnected() {
        #expect(
            ConnectionStatus.resolve(
                isPaired: true,
                isWatchAppInstalled: true,
                isReachable: true,
                activationState: 0
            ) == .inactive
        )
    }
}
