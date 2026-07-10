//
//  WireKeysTests.swift
//  SpottersaurusKitTests
//
//  Pins each `WireKeys` constant to its exact wire-contract string. These are
//  the WatchConnectivity dictionary keys shared by `WatchLink` (iPhone) and
//  `WatchPlannedSessionStore` (Watch) — a future accidental rename of any of
//  these values would compile fine on both sides but silently break the
//  transport at runtime, so this test is the regression guard.
//

import Testing
@testable import SpottersaurusKit

struct WireKeysTests {

    @Test func pinsExactWireKeyStrings() {
        #expect(WireKeys.plannedSession == "plannedSession")
        #expect(WireKeys.watchCommand == "watchCommand")
        #expect(WireKeys.finishedSession == "finishedSession")
        #expect(WireKeys.liveSetLifecycle == "liveSetLifecycle")
        #expect(WireKeys.liveTick == "liveTick")
    }
}
