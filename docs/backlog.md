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
