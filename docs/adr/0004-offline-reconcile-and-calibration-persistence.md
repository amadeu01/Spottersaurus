# Offline reconcile (snapshot-on-reconnect) and calibration persistence

Date: 2026-07-10
Status: Accepted

## Context

Two related durability gaps. (1) When the Watch→iPhone link drops mid-session,
the iPhone mirror missed the events that happened during the gap and could show
stale or wrong state after reconnect. (2) `CalibrationProfile` exists in the
SwiftData schema but nothing reads or writes it — the Watch's warmup capture is
in-memory and thrown away per set, detection never improves across sessions, and
iOS has no calibration surface at all.

## Decision

**Offline reconcile — snapshot-on-reconnect + durable finish:**

- Every live tick / Live Set Lifecycle Event carries a **monotonic sequence
  number**.
- Whenever reachability returns, the Watch pushes **one full Session Snapshot**
  (current set index, lifecycle state, rep count, Alert Stage). The iPhone folds
  it idempotently — gaps self-heal with no request/reply handshake.
- The finished-session envelope always travels the **durable queue**
  (`transferUserInfo`), so the historical record survives even if the phone was
  off for the entire session.
- Rejected: event-log replay/backfill (needs a request/reply protocol + journal
  retention for exact history we don't need) and accept-gaps-until-set-end
  (phone can look frozen for a long time).

**Calibration persistence loop:**

- Watch warmup capture **writes a `CalibrationProfile` per lift** (tempo baseline
  + velocity band) to SwiftData, CloudKit-mirrored.
- On arming a set the Watch **loads the saved profile** instead of always using
  `.fallback`, so calibration actually sharpens detection across sessions and
  survives restarts.
- iOS gets a **Calibration surface** (beside Maxes): per-lift current baseline,
  capture freshness, and Reset-to-fallback. Read/reset in v1; iOS-initiated
  guided recalibration is deferred.
