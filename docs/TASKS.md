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
- [ ] Verify: `swift test` (package) green; both app targets build via `xcodebuild`
      <!-- package `swift test` green; iOS target BUILD SUCCEEDED on iOS 26.5 sim;
           Watch target builds NOT verified — watchOS 26.5 simulator runtime not
           installed on the build machine (install via Xcode > Settings > Components). -->

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
- **Entitlements** (HealthKit, CloudKit `.private`, App Groups for WatchConnectivity)
  and **Info.plist usage strings** (Motion & Fitness, HealthKit, audio) — Phase 1
  checklist items above, not yet added.
- **Verify the Watch build**: install the watchOS 26.5 simulator runtime, then
  `xcodebuild build -scheme "Spottersaurus Watch App" -destination "platform=watchOS Simulator,name=<watch>"`.
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
           CloudKit-safe, since SwiftData relationship arrays are unordered. -->


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
- [ ] `HKWorkoutSession` (functional strength training) lifecycle
- [ ] `CMBatchedSensorManager` high-rate motion stream while set armed
- [ ] `HKLiveWorkoutBuilder` HR stream
- [ ] Wire live samples into `SpotEngine`; emit events
- [ ] Set lifecycle: arm → reps → auto-rack (motion settle) → rest → next
- [ ] Calibration flow on warmup sets
- [ ] Verify: on-device run (real IMU; Simulator can't)

## Phase 5 — Watch UI (native-ported design)
- [ ] Live set screen: rep counter, concentric velocity, weight, HR (monospaced digits)
- [ ] Concentric `Circle().trim` ring gauge per rep
- [ ] State tinting: neutral → amber (grinding) → red (RACK IT) with pulsing border
- [ ] Escalating alert: `.sensoryFeedback` haptics + audio cue + full-screen RACK IT
- [ ] Rest timer ring + completion haptic
- [ ] Crown-scrub weight/reps; 44pt targets; safe areas
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
- [ ] Persist finished session to SwiftData; write workout to HealthKit
- [ ] Verify: standalone Watch session appears in iPhone history + Apple Health

## Phase 7 — iPhone planner
- [ ] Today / Start screen; Send-to-Watch; standalone-start fallback
- [ ] Program builder: days → planned sets (exercise, sets×reps, weight/%1RM, AMRAP, rest)
- [x] Progression engine (pure math): 5/3/1 TM + week schemes, linear bump, %1RM→kg resolve (2026-07-08)
      <!-- TDD, hardware-free. Sources/.../Progression/ (core + FiveThreeOne +
           Linear). Rounds to barbell increment (nearest, tie away from zero).
           18 tests. Preset-load + auto-progress UI still to wire. -->
- [ ] Load 5/3/1 + linear presets; auto-progress weights from `UserMaxes` (wire engine into builder UI)
- [ ] Maxes editor; calibration view/reset
- [ ] Verify: build a program → loads on Watch

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
