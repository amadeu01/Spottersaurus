//
//  LiveSessionStateTests.swift
//  SpottersaurusKitTests
//
//  Headless tests for the pure Live Session state reducer (Phase 0.2, L3).
//  Time is always injected — no wall-clock reads — so staleness is tested
//  deterministically with synthetic `Date`s.
//

import XCTest
@testable import SpottersaurusKit

final class LiveSessionStateTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func armed(
        lift: LiftKind = .bench,
        targetReps: Int = 5,
        weightKg: Double = 100,
        setIndex: Int = 0,
        setCount: Int = 3,
        sequence: Int = 0
    ) -> LiveSetLifecycleEnvelope {
        .armed(lift: lift, targetReps: targetReps, weightKg: weightKg, setIndex: setIndex, setCount: setCount, sequence: sequence)
    }

    private func tick(
        repCount: Int = 1,
        currentVelocityMS: Double = 0.42,
        heartRateBPM: Double = 130,
        elapsedSeconds: TimeInterval = 12,
        alertStage: AlertStage = .none,
        setIndex: Int = 0,
        setCount: Int = 3,
        sequence: Int = 0
    ) -> LiveTickEnvelope {
        LiveTickEnvelope(
            repCount: repCount,
            currentVelocityMS: currentVelocityMS,
            heartRateBPM: heartRateBPM,
            elapsedSeconds: elapsedSeconds,
            alertStage: alertStage,
            setIndex: setIndex,
            setCount: setCount,
            sequence: sequence
        )
    }

    // MARK: - Initial state

    func test_initialState_isIdleWithNoIdentityOrMetrics() {
        let state = LiveSessionState()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.identity)
        XCTAssertNil(state.metrics)
        XCTAssertNil(state.lastEventAt)
    }

    // MARK: - armed -> active

    func test_armed_setsPhaseActiveWithIdentity() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(lift: .squat, targetReps: 5, weightKg: 140, setIndex: 0, setCount: 3), now: t0)

        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(state.identity, LiveSessionState.Identity(lift: .squat, targetReps: 5, weightKg: 140, setIndex: 0, setCount: 3))
        XCTAssertEqual(state.lastEventAt, t0)
    }

    // MARK: - ticks update metrics + N-of-M

    func test_tick_updatesMetricsAndSetNofM() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)

        let t1 = t0.addingTimeInterval(2)
        state.reduce(tick: tick(repCount: 2, currentVelocityMS: 0.55, heartRateBPM: 138, elapsedSeconds: 14, alertStage: .grinding, setIndex: 1, setCount: 4), now: t1)

        XCTAssertEqual(state.metrics, LiveSessionState.Metrics(
            repCount: 2,
            meanConcentricVelocityMS: 0.55,
            heartRateBPM: 138,
            alertStage: .grinding,
            elapsedSeconds: 14,
            setIndex: 1,
            setCount: 4
        ))
        XCTAssertEqual(state.lastEventAt, t1)
        // Ticks don't themselves change phase.
        XCTAssertEqual(state.phase, .active)
    }

    func test_tick_beforeAnyArmed_stillRecordsMetrics() {
        var state = LiveSessionState()
        state.reduce(tick: tick(repCount: 0), now: t0)

        XCTAssertNotNil(state.metrics)
        XCTAssertEqual(state.phase, .idle, "a stray tick shouldn't fabricate a phase change on its own")
    }

    // MARK: - ended -> ended

    func test_ended_setsPhaseEnded() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)
        state.reduce(tick: tick(), now: t0.addingTimeInterval(1))
        state.reduce(lifecycle: .ended(), now: t0.addingTimeInterval(2))

        XCTAssertEqual(state.phase, .ended)
        XCTAssertEqual(state.lastEventAt, t0.addingTimeInterval(2))
        // Identity/metrics are left as the last-known reading, not cleared.
        XCTAssertNotNil(state.identity)
        XCTAssertNotNil(state.metrics)
    }

    // MARK: - second armed (next set / new session) replaces identity, stays live

    func test_secondArmed_replacesIdentity_keepsSessionLive() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(lift: .bench, targetReps: 5, weightKg: 100, setIndex: 0, setCount: 3), now: t0)
        state.reduce(tick: tick(repCount: 5, setIndex: 0, setCount: 3), now: t0.addingTimeInterval(30))
        state.reduce(lifecycle: .ended(), now: t0.addingTimeInterval(31))

        let t1 = t0.addingTimeInterval(120)
        state.reduce(lifecycle: armed(lift: .bench, targetReps: 5, weightKg: 102.5, setIndex: 1, setCount: 3), now: t1)

        XCTAssertEqual(state.phase, .active)
        XCTAssertEqual(state.identity, LiveSessionState.Identity(lift: .bench, targetReps: 5, weightKg: 102.5, setIndex: 1, setCount: 3))
        XCTAssertEqual(state.lastEventAt, t1)
        XCTAssertNotEqual(state.phase, .idle)
    }

    // MARK: - staleness timeout

    func test_isStale_falseBeforeFiveMinutes() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)

        let justUnderTimeout = t0.addingTimeInterval(LiveSessionState.staleTimeout - 1)
        XCTAssertFalse(state.isStale(at: justUnderTimeout))
    }

    func test_isStale_trueAtOrAfterFiveMinutes() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)

        let atTimeout = t0.addingTimeInterval(LiveSessionState.staleTimeout)
        XCTAssertTrue(state.isStale(at: atTimeout))
    }

    func test_applyStalenessIfNeeded_endsSessionAfterFiveMinutesOfNoEvents() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)

        let past = t0.addingTimeInterval(LiveSessionState.staleTimeout + 1)
        state.applyStalenessIfNeeded(at: past)

        XCTAssertEqual(state.phase, .ended)
    }

    func test_applyStalenessIfNeeded_doesNothingBeforeTimeout() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)

        let soon = t0.addingTimeInterval(60)
        state.applyStalenessIfNeeded(at: soon)

        XCTAssertEqual(state.phase, .active)
    }

    func test_ticksArriving_resetTheStalenessClock_keepSessionAlive() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)

        // A tick arrives just before the original timeout would have fired.
        let heartbeat = t0.addingTimeInterval(LiveSessionState.staleTimeout - 5)
        state.reduce(tick: tick(), now: heartbeat)

        // Checking staleness shortly after that heartbeat (well within a
        // fresh 5-minute window from `heartbeat`) must NOT have timed out,
        // even though it's long past the original arm time.
        let afterOriginalTimeout = t0.addingTimeInterval(LiveSessionState.staleTimeout + 10)
        XCTAssertFalse(state.isStale(at: afterOriginalTimeout))

        state.applyStalenessIfNeeded(at: afterOriginalTimeout)
        XCTAssertEqual(state.phase, .active, "a recent tick should keep the session live past the original arm's timeout")
    }

    func test_applyStalenessIfNeeded_idleSession_neverStale() {
        var state = LiveSessionState()
        let farFuture = t0.addingTimeInterval(LiveSessionState.staleTimeout * 10)
        state.applyStalenessIfNeeded(at: farFuture)
        XCTAssertEqual(state.phase, .idle)
    }

    func test_applyStalenessIfNeeded_alreadyEnded_isNoOp() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0)
        state.reduce(lifecycle: .ended(), now: t0.addingTimeInterval(1))

        let farFuture = t0.addingTimeInterval(LiveSessionState.staleTimeout * 10)
        state.applyStalenessIfNeeded(at: farFuture)

        XCTAssertEqual(state.phase, .ended)
    }

    // MARK: - idempotent fold (ADR 0004: sequence-gated dedupe)

    func test_initialState_lastSequenceIsZero() {
        let state = LiveSessionState()
        XCTAssertEqual(state.lastSequence, 0)
    }

    func test_sequencedTicks_1_2_3_allApply_andAdvanceHighWaterMark() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(sequence: 1), now: t0)
        state.reduce(tick: tick(repCount: 1, sequence: 2), now: t0.addingTimeInterval(1))
        state.reduce(tick: tick(repCount: 2, sequence: 3), now: t0.addingTimeInterval(2))

        XCTAssertEqual(state.lastSequence, 3)
        XCTAssertEqual(state.metrics?.repCount, 2)
        XCTAssertEqual(state.lastEventAt, t0.addingTimeInterval(2))
    }

    func test_duplicateSequence_isIgnored_stateUnchanged() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(sequence: 1), now: t0)
        state.reduce(tick: tick(repCount: 1, sequence: 2), now: t0.addingTimeInterval(1))
        state.reduce(tick: tick(repCount: 3, sequence: 3), now: t0.addingTimeInterval(2))
        let stateAfterSeq3 = state

        // Re-folding sequence 2 (already folded) must be a complete no-op —
        // including not touching `lastEventAt`.
        state.reduce(tick: tick(repCount: 99, sequence: 2), now: t0.addingTimeInterval(10))

        XCTAssertEqual(state, stateAfterSeq3)
        XCTAssertEqual(state.metrics?.repCount, 3, "duplicate seq 2 must not overwrite the seq-3 metrics")
        XCTAssertEqual(state.lastSequence, 3)
    }

    func test_outOfOrderSequenceAfterNewer_isIgnored_stateMatchesLatest() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(sequence: 1), now: t0)
        state.reduce(tick: tick(repCount: 1, sequence: 2), now: t0.addingTimeInterval(1))
        state.reduce(tick: tick(repCount: 3, sequence: 3), now: t0.addingTimeInterval(2))
        let stateAfterSeq3 = state

        // A stale sequence-1 tick straggles in after sequence 3 already
        // folded — must be dropped, not rewind the metrics.
        state.reduce(tick: tick(repCount: 1, sequence: 1), now: t0.addingTimeInterval(20))

        XCTAssertEqual(state, stateAfterSeq3)
        XCTAssertEqual(state.metrics?.repCount, 3)
        XCTAssertEqual(state.lastSequence, 3)
    }

    func test_duplicateLifecycleSequence_isIgnored() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(lift: .bench, sequence: 1), now: t0)
        state.reduce(lifecycle: .ended(sequence: 2), now: t0.addingTimeInterval(1))
        let stateAfterEnded = state

        // A duplicate delivery of the same `armed` (seq 1) arrives late —
        // must not reopen the session or move the phase back to `.active`.
        state.reduce(lifecycle: armed(lift: .squat, sequence: 1), now: t0.addingTimeInterval(30))

        XCTAssertEqual(state, stateAfterEnded)
        XCTAssertEqual(state.phase, .ended)
        XCTAssertEqual(state.identity?.lift, .bench)
    }

    /// Legacy/unstamped stream (all events default `sequence == 0`, e.g. a
    /// pre-ADR-0004 Watch build) must NOT be dropped by the idempotency
    /// gate — every 0-stamped event keeps folding under today's
    /// last-writer-wins behavior, since 0 is the "no sequence info"
    /// sentinel, not a real high-water mark to compare against.
    func test_legacyAllZeroSequenceStream_stillFoldsLastWriterWins_notAllDropped() {
        var state = LiveSessionState()
        state.reduce(lifecycle: armed(), now: t0) // sequence defaults to 0
        state.reduce(tick: tick(repCount: 1), now: t0.addingTimeInterval(1))
        state.reduce(tick: tick(repCount: 2), now: t0.addingTimeInterval(2))
        state.reduce(tick: tick(repCount: 3), now: t0.addingTimeInterval(3))

        XCTAssertEqual(state.metrics?.repCount, 3, "every 0-stamped tick should still fold — last writer wins")
        XCTAssertEqual(state.lastEventAt, t0.addingTimeInterval(3))
        XCTAssertEqual(state.lastSequence, 0, "legacy 0-stamped events never advance the high-water mark")
    }
}
