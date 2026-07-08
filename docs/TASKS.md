# Spottersaurus — Build Tasks

Tracks execution of `docs/PLAN.md`. Mark `- [x]` with a completion date `(YYYY-MM-DD)`
when done. Spec lives in `docs/PLAN.md`.

Legend: `- [ ]` todo · `- [x] … (2026-06-29)` done.

---

## Phase 1 — Project setup
- [x] Create `Packages/SpottersaurusKit` local Swift package (Package.swift, iOS+watchOS platforms) (2026-06-29)
- [x] Package source dirs: `Model/`, `Detection/`, `Sync/`, `Design/`, plus `Tests/` (2026-06-29)
- [x] Add `Spottersaurus Watch App` watchOS target to the Xcode project (2026-06-29)
- [x] Link `SpottersaurusKit` to iOS + Watch targets (2026-06-29)
- [x] Entitlements: HealthKit, CloudKit (private), App Groups (WatchConnectivity) (2026-07-08)
      <!-- Added `Spottersaurus/Spottersaurus.entitlements` +
           `Spottersaurus Watch App/Spottersaurus Watch App.entitlements`
           (healthkit, icloud-services=CloudKit, container
           `iCloud.amadeu.dev.Spottersaurus`, app group
           `group.amadeu.dev.Spottersaurus`). CODE_SIGN_ENTITLEMENTS wired on all
           4 target configs. NOTE: capabilities must still be enabled on the App
           ID in the Developer portal before real-device/CloudKit signing. -->
- [x] Info.plist usage strings: HealthKit, Motion & Fitness, microphone/audio if needed (2026-07-08)
      <!-- INFOPLIST_KEY_NSHealthShareUsageDescription / NSHealthUpdateUsage /
           NSMotionUsageDescription on iOS + Watch configs. Audio alerts play via
           the workout session and need no usage string; mic not requested. -->
- [x] Design system tokens + reusable views (`Design/`) (2026-07-08)
      <!-- Phase-10 partial, hardware-free: Theme tokens + RingGauge / GlassCard /
           MetricReadout / PrimaryButton. Full end-to-end apply stays in Phase 10. -->
- [x] Delete template `Item.swift`; gut default `ContentView` (2026-06-29)
- [x] Verify: `swift test` (package) green; both app targets build via `xcodebuild` (2026-07-08)
      <!-- package `swift test` green: 63 XCTest tests + 18 Swift Testing tests.
           iOS target BUILD SUCCEEDED on iPhone 17 sim. Watch target BUILD
           SUCCEEDED with `generic/platform=watchOS Simulator`. -->

### Phase 1 — notes / remaining manual Xcode steps
The Watch target + package linkage were added programmatically via the `xcodeproj`
ruby gem (1.27.0) — the project is objectVersion 77 with synchronized root groups;
a lossless round-trip was validated before touching the real project, and
`xcodebuild -list` confirms the new `Spottersaurus Watch App` target + scheme and
that `SpottersaurusKit` resolves. The following were intentionally deferred (left
for Xcode / later phases to avoid risking the iOS build):
- **Embed Watch app into iOS app**: add the "Embed Watch Content" copy-files phase
  on the `Spottersaurus` target (and confirm companion pairing) in Xcode so the
  watch app ships inside the iOS app. The watch target builds standalone today.
- **Real-device capability check**: the entitlement files and usage strings are
  present, but HealthKit/CloudKit capabilities still need to be enabled on the
  App ID in the Developer portal before real-device signing and CloudKit testing.
- `Package.swift` uses `// swift-tools-version: 6.2` (not 6.0): `.iOS(.v26)` /
  `.watchOS(.v26)` require PackageDescription 6.2+. Toolchain is Swift 6.3.3, so 6.2
  is accepted; platforms remain `.v26` as specified.

## Phase 2 — Data model (SwiftData + CloudKit)
- [x] `LiftKind` enum + bar-tracking profile (wristTracked / backLoaded) (2026-06-30)
- [x] `Exercise`, `Program`, `ProgramDay`, `PlannedSet` (2026-06-30)
- [x] `WorkoutSession`, `CompletedSet`, `RepMetric` (2026-06-30)
- [x] `UserMaxes`, `CalibrationProfile`, `SpotterPairing` (2026-06-30)
- [x] Shared `ModelContainer` with `cloudKitDatabase: .private` (2026-06-30)
      <!-- `makeModelContainer(inMemory:cloudKit:)` uses CloudKit `.automatic`
           (mirrors to the private DB from the entitlement) for production and
           `.none` for in-memory/local; tests pass inMemory:true. -->
- [x] Seed presets: 5/3/1 and linear progression (2026-06-30)
- [x] Verify: model unit tests (insert/fetch/relationships) green (2026-06-30)
      <!-- `swift test` green: 11 tests pass (8 ModelTests + 3 LiftKindTests).
           iOS `Spottersaurus` scheme: BUILD SUCCEEDED on iPhone 17 sim.
           Ordered relationships use an explicit `sortIndex`/`repIndex` + sorted
           accessors (orderedDays/orderedSets/orderedRepMetrics) — robust and
           CloudKit-safe, since SwiftData relationship arrays are unordered.
           SwiftData relationship arrays are optional to satisfy CloudKit
           validation; callers use nil-safe ordered accessors/append helpers. -->


## Phase 3 — Detection engine (core risk, hardware-free)
- [x] `SampleBuffer` types (accel/device-motion/HR sample structs) (2026-06-30)
      <!-- `Detection/SampleBuffer.swift`: `Timestamped` protocol (MotionSample/
           HRSample conform), generic `SampleBuffer` windowing helper,
           gravity-removed `LinearSample`, and `GravityRemover` (EMA gravity
           estimate + bar-axis projection). MotionSample/HRSample seeds reused. -->
- [x] `RepSegmenter` — eccentric/concentric phase split from gravity-removed accel (2026-06-30)
      <!-- ZUPT-integrated velocity; phases read off velocity sign; "still" =
           sustained-quiet runs (>= minStillSeconds) so slow grinds aren't
           chopped at their low-accel velocity peak. Emits `RepPhase` timings. -->
- [x] `VelocityIntegrator` — concentric velocity estimate (VBT) with drift handling (2026-06-30)
      <!-- Trapezoid integrate + endpoint-zero detrend (ZUPT at phase boundaries
           / high-pass). Exposes mean + peak + displacement + full series. -->
- [x] `Calibration` — per-lift baseline tempo + velocity band from warmups (2026-06-30)
      <!-- Returns plain `CalibrationValues` (no SwiftData) the app maps onto
           `CalibrationProfile`; velocity band disabled for back-loaded lifts. -->
- [x] `SpotEngine` — conservative two-stage (Stage 1 grind → Stage 2 RACK IT) (2026-06-30)
      <!-- Emits `.grinding`/`.rackIt`/`.resolved` SpotEvents w/ timestamps +
           confidence + reason. Thresholds in `SpotConfig` (Phase-9 tunable). -->
- [x] Squat path: tempo + HR + manual grind tap (velocity disabled) (2026-06-30)
      <!-- backLoaded/!usesVelocityPath: tempo cadence + injected HR spike +
           manual tap; VelocityIntegrator never invoked (usedVelocityPath=false). -->
- [x] Unit tests: clean reps (no fire), grind (Stage 1), hard pin (Stage 2), false-alarm guard (2026-06-30)
- [x] Verify: `swift test` green incl. recorded/synthetic IMU fixtures (2026-06-30)
      <!-- `swift test`: 19 tests, 0 failures (8 new DetectionTests + 11
           existing ModelTests/LiftKindTests stay green). Synthetic in-code
           fixtures (sin² velocity bumps / grind plateau); no binary fixtures. -->

## Phase 4 — Watch session engine
- [x] `HKWorkoutSession` (functional strength training) lifecycle (2026-07-08)
      <!-- Watch-side adapter starts/ends a functional-strength HKWorkoutSession
           when the live set is armed/racked. Simulator and unauthorized devices
           fall back to manual dev controls without blocking the UI. -->
- [x] `CMBatchedSensorManager` high-rate motion stream while set armed (2026-07-08)
      <!-- `WatchMotionStreamAdapter` consumes CMBatchedSensorManager
           accelerometer async batches and maps them to platform-neutral
           MotionSample timestamps relative to set arm. -->
- [x] `HKLiveWorkoutBuilder` HR stream (2026-07-08)
      <!-- `WatchWorkoutSessionAdapter` listens for collected heart-rate
           statistics and maps most-recent HR to HRSample for the live set. -->
- [x] Wire live samples into `SpotEngine`; emit events (2026-07-08)
      <!-- `LiveSetViewModel` buffers motion/HR samples, runs the pure
           SpotEngine, increments reps from new RepResults, updates velocity,
           and feeds SpotEvents into SetLifecycleController. Real-device
           threshold tuning remains under on-device verification. -->
- [x] Set lifecycle state machine: arm → reps → auto-rack → rest → next (pure) (2026-07-08)
      <!-- TDD, hardware-free. Session/SetLifecycleController.swift: pure Sendable
           value type, states idle/armed/repping/racked/resting/complete +
           AlertStage none/grinding/rackIt. Injected time (no wall-clock), reuses
           SpotEvent. Illegal transitions ignored. 16 tests. Sensor/HK wiring
           (4a/4b) drives it on-device. -->
- [x] Calibration flow on warmup sets (2026-07-08)
      <!-- Watch live-set screen can capture warmup motion before arming a work
           set, derive CalibrationValues via the pure Calibration engine, show
           detected rep/tempo/velocity-band feedback, and rebuild SpotEngine
           with the calibrated baseline. Falls back to conservative defaults
           when no clean warmup rep is detected. -->
- [ ] Verify: on-device run (real IMU; Simulator can't)
      <!-- Simulator/build verification green; still needs a paired Apple Watch
           session to validate real IMU sample cadence, HealthKit authorization,
           and false-alarm behavior under load. -->

## Phase 5 — Watch UI (native-ported design)
- [x] Live set screen: rep counter, concentric velocity, weight, HR (monospaced digits) (2026-07-08)
      <!-- `Spottersaurus Watch App/Features/LiveSet` replaces the placeholder
           root with a deterministic live-set surface driven by
           `SetLifecycleController`. App dependencies live in `App/`; small
           watch renderers live in `Components/`. Hardware session wiring still
           replaces the local demo controls in Phase 4. -->
- [x] Concentric `Circle().trim` ring gauge per rep (2026-07-08)
      <!-- Uses shared `RingGauge` with rep/rest progress. -->
- [x] State tinting: neutral → amber (grinding) → red (RACK IT) with pulsing border (2026-07-08)
- [ ] Escalating alert: `.sensoryFeedback` haptics + audio cue + full-screen RACK IT
      <!-- Full-screen RACK IT + haptic trigger implemented; audio cue remains
           open until the real watchOS session/audio path is wired. -->
- [ ] Rest timer ring + completion haptic
      <!-- Rest progress display exists in `LiveSetView`; completion haptic
           remains open until real timer/session wiring exists. -->
- [ ] Crown-scrub weight/reps; 44pt targets; safe areas
      <!-- Digital Crown adjusts load; buttons use 44pt minimum hit targets.
           Target reps now come from the injected `WatchPlannedSet`; real data
           should arrive through WatchLink once session loading exists. -->
- [ ] Verify: visual pass on Watch, dark-first OLED

## Phase 6 — Sync (Watch ↔ iPhone)
- [x] `SessionEnvelope` Codable DTOs (2026-07-08)
      <!-- TDD, hardware-free. Expanded Sync/SessionEnvelope.swift: RepMetric/
           SpotEvent/Calibration/LiveTick envelopes + richer CompletedSetEnvelope
           (per-rep metrics, spot events, avg/peak velocity, Epley e1RM). Reuses
           SpotEventKind/SpotReason + Epley (no dup). 8 round-trip tests.
           NOTE: WatchLink encoder must set JSONEncoder.dateEncodingStrategy =
           .iso8601 — Foundation's default is a raw reference-date double. -->
- [ ] `WatchLink` WCSession wrapper: live set streaming + finished-session handoff
- [x] Persist finished session to SwiftData (envelope→model importer) (2026-07-08)
      <!-- TDD, hardware-free. Persistence/SessionImporter.swift: upsert-by-id
           (no dupes on re-delivery), rep order via repIndex, SpotEvent→
           SpotterEvent (.resolved dropped — no matching stage), find-or-create
           Exercise per LiftKind. In-memory ModelContext tests. 6 tests. -->
- [ ] Write finished workout to HealthKit (on-device)
- [ ] Verify: standalone Watch session appears in iPhone history + Apple Health

## Phase 7 — iPhone planner
- [x] Today / Start screen; Send-to-Watch; standalone-start fallback (2026-07-08)
      <!-- SwiftData-backed Today tab shows the active program/day and resolved
           planned-set loads. Send-to-Watch builds a `PlannedSessionEnvelope`
           and sends it through the iOS `WatchLink` adapter (live message when
           reachable, queued application context/userInfo otherwise). Watch app
           consumes the same envelope via `WatchPlannedSessionStore`, persists
           the last received session, and falls back to a local standalone set
           when no iPhone handoff exists. -->
- [x] Program builder: days → planned sets (exercise, sets×reps, weight/%1RM, AMRAP, rest) (2026-07-08)
      <!-- `Features/Programs/Builder`: draft-based builder can create custom
           Programs, add/edit/reorder/delete ProgramDays and PlannedSets, choose
           lift/accessory exercise, reps, absolute or % training-max load,
           AMRAP, and rest. Saves into SwiftData domain models. -->
- [x] Progression engine (pure math): 5/3/1 TM + week schemes, linear bump, %1RM→kg resolve (2026-07-08)
      <!-- TDD, hardware-free. Sources/.../Progression/ (core + FiveThreeOne +
           Linear). Rounds to barbell increment (nearest, tie away from zero).
           18 tests. Preset-load + auto-progress UI still to wire. -->
- [ ] Load 5/3/1 + linear presets; auto-progress weights from `UserMaxes` (wire engine into builder UI)
      <!-- Partial (2026-07-08): Programs tab can insert the existing 5/3/1 and
           linear presets, browse days/sets, delete programs, and resolve loads
           from UserMaxes. Auto-progress after logged sessions remains open. -->
- [ ] Maxes editor; calibration view/reset
      <!-- Partial (2026-07-08): Maxes tab creates/edits SBD training max + 1RM
           records. Calibration profile view/reset remains open. -->
- [x] Verify: build a program → loads on Watch (2026-07-08)
      <!-- Hardware-free verification: `PlannedSessionEnvelope.make(program:day:maxes:)`
           resolves % training-max and absolute loads into ordered Watch-ready
           sets (2 tests). iOS and Watch simulator builds both succeed. Real
           phone-to-watch delivery still needs paired-device validation. -->

## Phase 8 — iPhone review / analytics
- [ ] History list → session → set detail (per-rep metrics, spotter events, e1RM)
- [x] Analytics compute layer (pure): e1RM trend, tonnage series, VBT velocity-at-load, spotter-event freq (2026-07-08)
      <!-- TDD, hardware-free. Sources/.../Analytics/ (SetRecord value type +
           PerformanceAnalytics pure funcs). Reuses Epley (no dup). 11 tests.
           Charts UI below consumes these. -->
- [ ] Swift Charts: e1RM trend, volume/tonnage, VBT velocity-at-load, spotter-event freq (wire to Analytics layer)
- [ ] Verify: charts render from real logged sessions

## Phase 9 — Human spotter
- [ ] `SpotterPairing` invite UI (CloudKit share / contact); per-lift enable
- [ ] APNs/CloudKit push on Stage-2 alert to paired spotter
- [ ] Verify: trigger Stage-2 with paired spotter → push arrives

## Phase 10 — Design polish
- [ ] `SpottersaurusKit/Design/Theme.swift` tokens (colors, type ramp, spacing)
- [ ] Reusable views: `RingGauge`, `GlassCard`, `MetricReadout`, `PrimaryButton`
- [ ] Apply design system end-to-end; light + dark
- [ ] Motion/haptics on press + state change; 44pt targets; safe areas audit
- [ ] Verify: full visual pass both devices, both appearances
