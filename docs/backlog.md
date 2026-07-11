# Backlog — sized, agent-deliverable tasks

Execution breakdown of [`PLAN.md`](PLAN.md). Every deliverable here is **S** or
**M** — the only sizes handed to an agent. **L** / **XL** items are shown only as
parents, already split into S/M subtasks.

## Rules of engagement

- **Sizes.** `S` ≈ one file/area, < ~150 LOC, no cross-cutting change. `M` ≈ one
  feature slice, a few files, single responsibility. `L` ≈ multi-file feature
  (split below). `XL` ≈ whole subsystem (split below).
- **Delivery.** Each S/M task → one `ios-engineer` (Sonnet) subagent, given the
  task's Goal + Done-when. Never hand an agent an L/XL parent.
- **Validation.** Every task is validated with `/tdd` — tests first, then
  implementation, red→green. Kit logic is tested with `swift test` on macOS (the
  reliable gate); do **not** gate on the iOS simulator.
- **Commit.** One commit per completed S task (and per M subtask). Message names
  the task id, e.g. `P1-1a: resolve alert from any lifecycle state`.
- **Order.** Top-to-bottom within a phase; a subtask's prerequisites are its
  siblings above it unless noted.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done (add date).

---

## Phase 1 — Stabilize (safety-critical, ships first)

### P1-1 — Fix stuck `RACK IT` — **L** → split

- [x] **P1-1a** `S` · Kit · **SetLifecycleController: resolve from any state.** (2026-07-10)
  Goal: `.resolved` clears `alertStage` regardless of `state` (currently guarded
  to `.repping`). Done-when: unit tests prove resolve clears from `.racked`,
  `.resting`, `.complete`; existing tests green.
- [x] **P1-1b** `S` · Kit · **SetLifecycleController: auto-clear on auto-rack.** (2026-07-10)
  Goal: `autoRack()` also resets `alertStage` to `.none` (bar settled ⇒ danger
  over). Done-when: test asserts a `.rackIt` stage clears on `autoRack()`.
- [x] **P1-1c** `M` · Watch · **LiveSetViewModel: high-water-mark event feed.** (2026-07-10)
  Goal: only *new* `SpotEngine` events reach `lifecycle.handle(...)` — stop
  replaying the whole `analysis.events` buffer each tick (mirror the existing
  `spotEvents` dedup). Done-when: a test-double SpotEngine returning the same
  event twice raises the alert once; after `resolveAlert()` the same event does
  **not** re-raise, but a genuinely new event does.
- [x] **P1-1d** `S` · Kit · **CompletedSet: resolve/false-alarm marker.** (2026-07-10)
  Goal: record a manual-resolve marker on the completed set for later tuning.
  Done-when: envelope + model round-trip test covers the new field.

### P1-2 — Watch reconnect hardening — ~~S~~ **moved to P2-8b**

- [x] **P1-2** — ~~Watch adapter re-activates on `sessionDidDeactivate`.~~
  **Struck:** `sessionDidDeactivate` / `sessionDidBecomeInactive` are **iOS-only**
  WatchConnectivity delegate methods (paired-watch switching); they don't exist on
  watchOS, so this literal task is a no-op there. The genuine work —
  "auto-reactivate on activation failure" — is folded into **P2-8b** (keepalive),
  where both adapters' reactivation is handled together. (2026-07-10)

---

## Phase 1.5 — Detection realism (hands-locked reality)

Pure `Detection` changes from ADR 0005 (no mid-rep manual input) and ADR 0006
(unrack/setup phase). All Kit-testable on macOS — high value, since without them
the walkout counts as a rep and squat leans on an impossible tap.

### P15-D1 — Drop manual tap from live detection — **S**

- [x] **P15-D1** `S` · Kit · **Remove `manualTaps` from `SpotEngine`; squat (2026-07-10)
  Stage-2 = tempo-blowout OR (tempo + HR).** Goal: delete the `tapped` signal
  from `analyzeVelocityPath`/`analyzeTempoPath`; squat Stage 2 fires on
  `ratio > rackDurationMultiplier` alone OR (moderate blowout AND HR spike).
  Done-when: DetectionTests updated — a slow squat rep with no HR still reaches
  RACK IT; a tap no longer influences anything (param removed or ignored);
  `swift test` green.

### P15-S1 — Device-motion sample type — **M** (ADR 0007)

- [x] **P15-S1** `M` · Kit · **Add a fused device-motion sample type.** (2026-07-10)
  Goal: a pure Codable `DeviceMotionSample` (timestamp + `userAcceleration` xyz,
  `gravity` xyz, `rotationRate` xyz, `attitude` quaternion) beside `MotionSample`;
  a bar-axis front end that projects onto the supplied gravity vector (falls back
  to `GravityRemover` EMA when only raw accel is available). Done-when: unit tests
  cover projection-with-supplied-gravity vs EMA fallback on synthetic buffers;
  `swift test` green.

### P15-S2 — Watch feed uses `deviceMotionUpdates` — **M** (ADR 0007)

- [ ] **P15-S2** `M` · Watch · **Stream fused device motion (200 Hz).**
  Goal: `WatchMotionStreamAdapter` uses `CMBatchedSensorManager.deviceMotionUpdates()`
  producing `DeviceMotionSample`; keep accelerometer + `CMMotionManager` fallbacks.
  Done-when: builds; on-device the pipeline runs off fused motion. (Device-side —
  Kit consumers carry the tests.)

### P15-S3 — Rotation/attitude gating in detection — **M** (ADR 0007)

- [ ] **P15-S3** `M` · Kit · **(defer — needs real captures)** Use rotation/attitude
  to reject non-rep motion. Goal: `RepSegmenter`/`SpotEngine` use
  `rotationRate`/`attitude` to reject walkout/torso-sway. The rejection threshold
  is a hand-tuned heuristic best set from real captures (ADR 0008) rather than
  synthetic guesses — deferred alongside P15-SQ2 until on-device data exists.
  Done-when: walkout-with-rotation buffer yields no reps while clean reps segment;
  `swift test` green.

### P15-SQ1 — Compute squat velocity (don't trigger on it yet) — **M** (ADR 0009)

- [x] **P15-SQ1** `M` · Kit · **Squat computes velocity via fused-gravity; trigger
  stays tempo/HR.** (2026-07-10) Goal: split `LiftKind` capability into `computesVelocity`
  (true for squat too) vs `velocityDrivesAlerts` (bench/deadlift only for now);
  `SpotEngine` runs the velocity integrator for squat and reports Mean Concentric
  Velocity / peak / displacement, but the squat *alert* trigger stays tempo+HR
  (ADR 0005). Done-when: a squat buffer yields non-zero velocity metrics; squat
  Stage-1/2 still fire on tempo/HR only (a fast squat with low velocity does NOT
  alarm); bench/deadlift unchanged; `swift test` green.

- [ ] **P15-SQ2** `S` · Kit · **(parked, needs data)** Promote squat velocity to a
  trigger (or hybrid) once raw captures (ADR 0008) validate wrist-VBT tracks bar
  velocity. Blocked on capture + replay analysis.

### P15-D2 — Settle + rep-1 gate in segmenter — **M**

- [x] **P15-D2** `M` · Kit · **Ignore setup motion; gate rep 1 per lift.** (2026-07-10)
  Goal: `RepSegmenter` ignores pre-settle motion and gates the first rep on the
  lift-appropriate pattern (eccentric→concentric for squat/bench;
  concentric-from-rest for deadlift). Done-when: synthetic buffer with a walkout
  + N clean reps yields exactly N reps; deadlift-from-floor buffer counts rep 1;
  `swift test` green.

### P15-D3 — `.settling` lifecycle state — **S**

- [x] **P15-D3** `S` · Kit · **`SetLifecycleController`: add `.settling`.** (2026-07-10)
  Goal: `armed → settling → repping`; motion during `.settling` isn't a rep;
  transition driven by the segmenter's rep-1 gate. Done-when: state-transition
  tests cover armed→settling→repping and that a walkout in `.settling` doesn't
  advance repCount; `swift test` green. Landed as `arm() → .settling` directly
  (no reachable `.armed` state remained — no separate hands-free "I'm set"
  press per ADR 0006 — so `.armed` was removed from `SetLifecycleState` rather
  than kept dead alongside `.settling`). Watch VM/View/Controls call sites that
  still switch on `.armed` (`LiveSetViewModel.swift`, `LiveSetView.swift`,
  `LiveSetControlsView.swift`) are now stale pending P15-D4.

### P15-D4 — Wire Watch flow + remove grind-tap UI — **S**

- [x] **P15-D4** `S` · Watch · **`LiveSetViewModel` setup flow.** (2026-07-10) Goal: `arm()`
  enters `.settling`; auto-advance to live on the first gated rep; remove/repurpose
  any live "grind tap" affordance (`flagGrinding`/`rackIt`/controls) to match
  ADR 0005. Done-when: builds; Kit-side logic already covered by D1–D3.

---

## Phase 1.6 — Raw sensor capture & replay (ADR 0008)

Keep every raw sample per set, transfer durably to the iPhone, reprocess offline.
Debug/tuning asset — local files, not CloudKit.

### PRC-1 — Capture format + exporter — **M**

- [ ] **PRC-1** `M` · Kit · **Versioned capture container + NDJSON/CSV export.**
  Goal: a `Codable` `RawSetCapture` (schema version, session id, set id, lift,
  arm date, `[DeviceMotionSample]`, `[HRSample]`, lifecycle markers) with compact
  binary encode/decode and an NDJSON/CSV exporter. Done-when: round-trip +
  old-version-decodes tests; export test; `swift test` green.

### PRC-2 — Watch capture recorder — **M**

- [ ] **PRC-2** `M` · Watch · **Buffer arm→end per set; `transferFile` on end.**
  Goal: record all device-motion + HR samples for the set (incl. setup), write a
  `RawSetCapture` file, `WCSession.transferFile` it when the set ends. Bounded
  memory / streamed to disk. Done-when: on-device a completed set produces a file
  that arrives on the phone. (Device-side; Kit format carries the tests.)

### PRC-3 — iPhone receive + store + retention — **M**

- [ ] **PRC-3** `M` · iPhone · **Receive, group workout→exercise→set, prune.**
  Goal: accept the transferred file, store locally referenced by set id from
  `WorkoutSession`/`CompletedSet`, grouped by workout/exercise/set; keep-last-N
  retention + manual delete. Done-when: files land, are listable per set, prune
  works.

### PRC-4 — Offline replay through the engine — **S**

- [ ] **PRC-4** `S` · Kit · **Replay a capture through `SpotEngine`.**
  Goal: a pure function that feeds a `RawSetCapture` back through the pipeline to
  reproduce events/metrics deterministically. Done-when: replaying a recorded
  buffer yields the same `SpotAnalysis`; `swift test` green.

### PRC-5 — Debug surface: list / export / replay — **S**

- [ ] **PRC-5** `S` · iPhone · **Captures in the Debug tab.** Goal: list captures
  per set, export NDJSON/CSV, re-run the engine and show results — extends
  `Features/Debug`. Done-when: renders; export + replay invoke PRC-1/PRC-4.

---

## Phase 2 — Restructure transport & sync

### P2-3 — Shared `WireKeys` — **S**

- [x] **P2-3** `S` · Kit + both apps · **`WireKeys` single source of truth.** (2026-07-10)
  Goal: move the WCSession message-key literals into a Kit `WireKeys` enum; both
  targets reference it (removes the comment-synced duplication). Done-when: no
  string-literal keys remain in `WatchLink` / `WatchPlannedSessionStore`; a
  key-name test exists.

### P2-4 — `SessionTransport` port + domain — **XL** → split

- [ ] **P2-4a** `M` · Kit · **Define the `SessionTransport` port.**
  Goal: protocol for send/receive/reachability + reconcile hooks; relocate the
  envelope + `LiveTickCoalescer` under it. Done-when: port compiles in Kit,
  macOS-testable, no WatchConnectivity import.
- [ ] **P2-4b** `M` · Kit · **Pure transport core.**
  Goal: send/queue/fallback/coalesce decision logic as a pure type driving the
  port. Done-when: tests cover coalesce-to-latest + fallback ordering.
- [ ] **P2-4c** `M` · Kit · **Durable offline queue semantics.**
  Goal: model the durable-queue + reachable-vs-queued decision. Done-when: tests
  cover queued-while-unreachable then flush-on-reachable.

### P2-5 — App adapters — **L** → split

- [ ] **P2-5a** `M` · iPhone · **`WatchLink` → `WCSessionTransport` adapter.**
  Goal: reduce `WatchLink` to a thin adapter conforming to the port. Done-when:
  behavior parity; adapter holds only OS wiring.
- [ ] **P2-5b** `M` · Watch · **`WatchPlannedSessionStore` → adapter.**
  Goal: same on the Watch side. Done-when: parity; transport logic now lives in
  Kit.

### P2-6 — Watch-authoritative Live Session — **L** → split

- [ ] **P2-6a** `M` · iPhone · **iPhone Mirror folds events (single writer).**
  Goal: every iPhone live surface reads the `LiveSessionState` reducer; iPhone
  never advances its own cursor. Done-when: mirror is derived, not re-computed.
- [ ] **P2-6b** `S` · iPhone · **Remove superseded tick-recency heuristic.**
  Goal: delete `PhoneWatchSessionMonitor.lastTickReceivedAt` (+ `lastTick` if
  unused) once no reader remains. Done-when: monitor is connection-flags only.

### P2-7 — Sequence numbers + Session Snapshot — **L** → split

- [ ] **P2-7a** `S` · Kit · **Sequence number + idempotent fold.**
  Goal: add a monotonic seq to tick/lifecycle envelopes; reducer folds
  idempotently and ignores stale seq. Done-when: out-of-order/duplicate fold
  tests pass.
- [ ] **P2-7b** `M` · Watch + iPhone · **Session Snapshot on reconnect.**
  Goal: Watch emits one full snapshot on reachability-regained; iPhone folds it.
  Done-when: Kit fold test + on-device dropout self-heals.
- [ ] **P2-7c** `S` · Watch · **Finished session always durable.**
  Goal: guarantee finished-session via `transferUserInfo`. Done-when: test/log
  confirms delivery when phone was unreachable throughout.

### P2-8 — Keepalive & liveness — **L** → split

- [ ] **P2-8a** `M` · Kit · **Heartbeat-recency liveness.**
  Goal: derive "live" from heartbeat recency, not raw `isReachable`; feed
  `ConnectionStatus`. Done-when: reducer tests for blip-tolerance + stale window.
- [ ] **P2-8b** `M` · Watch + iPhone · **`HKWorkoutSession` keepalive + reactivation.**
  Goal: workout session spans the whole block; **both adapters auto-reactivate on
  activation failure/error** (absorbs the real intent of P1-2 — note watchOS has
  no `sessionDidDeactivate`, so reactivate off activation-error /
  `activationDidComplete`, not the iOS-only deactivate callbacks). Done-when:
  on-device session survives fg/bg without a false drop; a forced re-activation
  recovers the link.

### P2-9 — iPhone launches Watch — **M**

- [ ] **P2-9** `M` · iPhone · **`startWatchApp(with: HKWorkoutConfiguration)`.**
  Goal: Send-to-Watch wakes the Watch into the armed workout. Done-when:
  on-device, sending from iPhone launches the Watch app into the set.

### P2-10 — Split `LiveSetViewModel` — **M**

- [ ] **P2-10** `M` · Watch + Kit · **Extract sensor-buffer aggregator.**
  Goal: move motion/HR buffers + telemetry timestamps into a pure Kit
  aggregator; ViewModel keeps orchestration. Done-when: aggregator unit-tested;
  ViewModel shrinks. (Addresses the audit God-ViewModel finding.)

---

## Phase 3 — Calibration loop

### P3-11 — Persist Calibration Profile — **M** → split

- [ ] **P3-11a** `S` · Kit · **Calibration repository.**
  Goal: read/write `CalibrationProfile` per lift (Persistence). Done-when:
  upsert + fetch tests pass in-memory.
- [ ] **P3-11b** `M` · Watch · **Warmup capture persists.**
  Goal: `finishWarmupCalibration` writes via the repository. Done-when: profile
  survives app restart.

### P3-12 — Load on arm — **S**

- [ ] **P3-12** `S` · Watch · **Arm loads saved profile.**
  Goal: arming loads the persisted profile instead of `.fallback`. Done-when:
  test confirms saved values feed the `SpotEngine`.

### P3-13 — iOS Calibration surface — **M**

- [ ] **P3-13** `M` · iPhone · **Calibration section (view + reset).**
  Goal: per-lift baseline, capture freshness, Reset-to-fallback, beside Maxes.
  Done-when: renders live data; reset clears the profile.

---

## Phase 4 — Finish solo v1

### P4-14 — Settings — **M**

- [ ] **P4-14** `M` · iPhone · **Settings.** Detection sensitivity
  (conservative/sensitive/safety-max), units, audio cue, Health permissions.

### P4-15 — Spotter Pairing (CloudKit-share, no APNs) — **XL** → split

- [ ] **P4-15a** `M` · Kit · **Pairing model + enabled-lifts scope.**
- [ ] **P4-15b** `M` · iPhone · **CloudKit share invite flow.**
- [ ] **P4-15c** `M` · iPhone · **In-app Stage-2 alert surfacing on sync.**
  (No real-time push — the timeliness limit is intentional.)

### P4-16 — Design polish pass — **L** → split

- [ ] **P4-16a** `S` · **iPhone surface token audit** (light/dark, 44pt, insets).
- [ ] **P4-16b** `S` · **Watch surface token audit** (bezel, AOD variant).
- [ ] **P4-16c** `S` · **Motion & haptics pass** (press-scale, state-change).

---

## Delivery checklist (per task)

1. Spawn an `ios-engineer` (Sonnet) agent with the task Goal + Done-when.
2. Agent works `/tdd`: write failing tests → implement → green.
3. Kit tasks: `cd Packages/SpottersaurusKit && swift test` must pass.
4. Review the diff; then commit with the task id.
5. Mark `[x]` here with the date.
