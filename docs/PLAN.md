# Spottersaurus — Plan

Powerlifting **auto-spotter** for Apple Watch + iPhone. The Watch watches the bar
(wrist motion + HR) during a working set and, on a detected stall/grind/pin,
fires an escalating self-alert (`grinding` nudge → loud `RACK IT`) so a solo
lifter knows to bail. iPhone plans and reviews; the Watch is the in-gym executor.

> Vocabulary is in [`CONTEXT.md`](../CONTEXT.md). Architectural decisions are in
> [`docs/adr/`](adr/). Read those before non-trivial work.

## Locked product decisions

| Branch | Decision |
|---|---|
| Core concept | Watch auto-spotter — detect bar stall, self-alert lifter |
| Lift scope | Squat, bench, deadlift (SBD) |
| Squat detection | Tempo + HR + manual grind tap (wrist static on back-loaded bar) |
| Bench/dead detection | Wrist-motion stall / velocity collapse (VBT path) |
| Spot action | Self-alert (haptic + audio), two-stage escalation, conservative |
| Device roles | **Watch = authoritative live executor** (standalone-capable); iPhone = plan + review + **mirror** |
| Data stack | SwiftData local + CloudKit private mirror; WatchConnectivity live link; HealthKit write |
| Detection | On-device heuristic + **persisted per-user Calibration Profile** (no ML in v1) |
| Live velocity | Mean Concentric Velocity per rep (resolved at rep completion), not intra-rep trace |
| v1 boundary | Solo auto-spotter complete; **Spotter Pairing = CloudKit-share + in-app surfacing only, no APNs** |

## Current state (2026-07)

Built and green (Kit unit-tested on macOS via `swift test`): full SwiftData
schema + CloudKit config; pure detection engine (`SpotEngine`, `RepSegmenter`,
velocity integrator, `Calibration`); Watch live-set execution with sensors,
escalating alert UI, multi-set cursor; iPhone planner (builder, presets, maxes,
Today/Send-to-Watch, Session Override), history, Swift Charts analytics, profile,
debug log viewer; `WCSession` live-tick + finished-session + lifecycle transport.

### Known defects driving this plan

- **A — stuck `RACK IT`.** The red overlay can't be dismissed and blocks starting
  a new set. Root: `SetLifecycleController.handle(spotEvent:)` ignores `.resolved`
  unless `state == .repping`, so a resolve after rack is dropped; and
  `LiveSetViewModel.ingestMotionSamples` replays the whole `SpotEngine` event
  buffer every tick, re-raising the alert. (Safety-critical.)
- **B — Watch cuts connection.** Liveness derived from raw `isReachable` (flaps on
  fg/bg); Watch adapter never re-activates a deactivated session.
- **C — out of sync on send.** iPhone and Watch each own a cursor with no
  authority; iPhone only learns the current set via live ticks that stop on a
  dropout; wire keys duplicated across targets.
- **D — no calibration on iOS.** `CalibrationProfile` is in the schema but never
  read/written; Watch capture is ephemeral; iOS has no surface.

## Architecture (target)

Three targets: **Spottersaurus** (iOS), **Spottersaurus Watch App** (watchOS),
**SpottersaurusKit** (shared local package: `Model/ Detection/ Session/ Sync/
Analytics/ Progression/ Persistence/ HealthKit(ports)/ Diagnostics/ Design/`).

Post-restructure shape (ADR 0002):

- **Watch authoritative, iPhone mirrors.** One writer of Live Session state.
- **Hexagonal Session Transport.** A `SessionTransport` **port** + all
  send/queue/reconcile logic + `WireKeys` + envelopes live in Kit (macOS-testable);
  a thin `WCSessionTransport` **adapter** per app target holds the OS wiring.
  `WatchLink` / `WatchPlannedSessionStore` shrink to adapters.
- **Keepalive = `HKWorkoutSession`; liveness = Heartbeat recency** (ADR 0003).
- **Reconcile = Session Snapshot on reconnect + durable finished-session** (ADR 0004).

## Roadmap — stabilize → restructure → calibration → finish

### Phase 1 — Stabilize (safety-critical, ships first)

Small, targeted patches on the current structure so lifters can bail safely
before the big refactor.

1. **Fix stuck `RACK IT` (Bug A).**
   - Feed only **new** `SpotEngine` events into the lifecycle via a high-water
     mark (mirror the existing `spotEvents` dedup); stop replaying the buffer.
   - Allow `.resolved` to clear `alertStage` from **any** state, not only
     `.repping`.
   - Auto-clear the alert on auto-rack (bar settled ⇒ danger over).
   - Behavior: **clear + re-armable** — a genuinely new grind later in the same
     set can re-alert; the same event never re-fires. Record a resolve/false-alarm
     marker on the `CompletedSet`.
   - Tests (Kit): resolve from `.racked`/`.resting`/`.complete` clears; replayed
     buffer does not re-raise; a new event after resolve does raise.
2. **Watch reconnect hardening (partial Bug B).** Add the missing Watch-side
   `sessionDidDeactivate` reactivation; keep the manual reconnect card.

Exit: on-device, a deliberate grind escalates and can always be dismissed; a new
set arms cleanly afterward.

### Phase 2 — Restructure transport & sync (Bugs B + C, Opportunity E)

Implements ADR 0002 / 0003 / 0004 (reconcile half).

3. **Kit: `WireKeys` + envelope home.** Single source of truth for WCSession
   message keys; remove the duplicated literals in both targets.
4. **Kit: `SessionTransport` port + domain.** Move send/queue/fallback/coalesce
   logic and the offline queue into Kit behind the port; keep it pure and
   macOS-testable. `LiveTickCoalescer` already lives here.
5. **App adapters.** Reduce `WatchLink` and `WatchPlannedSessionStore` to
   `WCSessionTransport` adapters conforming to the port.
6. **Watch-authoritative Live Session.** Collapse to one writer; the iPhone
   `Mirror` folds streamed events. Remove the superseded
   `PhoneWatchSessionMonitor.lastTickReceivedAt` heuristic once all surfaces read
   the reducer.
7. **Sequence numbers + Session Snapshot.** Stamp ticks/lifecycle with a monotonic
   Sequence Number; push a full snapshot on reachability-regained; fold
   idempotently. Finished-session always via the durable queue.
8. **Keepalive.** Guarantee `HKWorkoutSession` runs for the whole block; derive
   liveness from Heartbeat recency; both adapters auto-reactivate.
9. **iPhone launches Watch.** "Send to Watch" uses
   `HKHealthStore.startWatchApp(with: HKWorkoutConfiguration)` to wake the Watch
   into the armed session.
10. **Refactor audit follow-ups.** Extract the sensor-buffer/telemetry bookkeeping
    out of `LiveSetViewModel` into a pure Kit aggregator (addresses the God-ViewModel
    finding) as this phase touches that code anyway.

Exit: send/resend never desyncs the current set; a mid-set dropout self-heals on
reconnect; transport logic is covered by Kit tests.

### Phase 3 — Calibration loop (Bug D)

Implements ADR 0004 (calibration half).

11. **Persist Calibration Profile.** Watch warmup capture writes a
    `CalibrationProfile` per lift (tempo baseline + velocity band) to SwiftData,
    CloudKit-mirrored.
12. **Load on arm.** Arming a set loads the saved profile instead of `.fallback`.
13. **iOS Calibration surface.** Beside Maxes: per-lift baseline, capture
    freshness, Reset-to-fallback. (iOS-initiated guided recalibration deferred.)

### Phase 4 — Finish solo v1

14. **Settings.** Detection sensitivity (conservative default; sensitive /
    safety-max), units, audio-cue choice, Health permissions.
15. **Spotter Pairing (CloudKit-share, no APNs).** Invite via CloudKit share,
    choose which lifts surface alerts; the spotter sees Stage-2 alerts **in-app on
    sync** (not real-time). Timeliness limit is explicit.
16. **Design polish pass.** End-to-end token audit, motion/haptics, light/dark on
    both devices; 44pt targets; safe-area insets.

## Explicitly out of scope (future, not this plan)

- **Real-time spotter push (APNs + server).** No push server exists (ADR 0001);
  Live Activities can't substitute (ADR 0003). Would be a separate backend effort.
- **On-device ML detection.** v1 stays heuristic + calibration.
- **iOS-initiated guided recalibration.**

## Verification per phase

- **Kit logic** (every phase): `swift test` on macOS — the reliable gate.
  Detection, lifecycle, transport, reconcile, and calibration math are all pure
  and tested there. Do **not** gate on iOS-sim `xcodebuild` (unreliable in the
  agent harness).
- **On-device** (Phase 1/2): real bench/deadlift set on Apple Watch — grind
  escalates and dismisses; a new set arms; forcing a reachability drop mid-set
  and restoring it self-heals the iPhone mirror; "Send to Watch" wakes the Watch
  into the armed session.
- **CloudKit** (Phase 3/4): second signed-in device sees synced Calibration
  Profiles, programs, history, maxes.
- **Design** (Phase 4): visual pass light + dark, both devices, against the
  ported tokens.
