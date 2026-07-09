# Spottersaurus — Build Tasks

Tracks execution of `docs/PLAN.md`. Mark `- [x]` with a completion date `(YYYY-MM-DD)`
when done. Spec lives in `docs/PLAN.md`.

Legend: `- [ ]` todo · `- [x] … (2026-06-29)` done.

---

## Phase 0 — Foundation: Reliability & Observability

> Inserted 2026-07-09. Phase 9 (human spotter) + Phase 10 (design polish) are
> **frozen** until Phase 0 lands. Origin: user reported the app is a black box —
> can't tell if SwiftData saves, when the Watch is connected, why HealthKit never
> synced (never authorized), that most Watch data looks mocked, small tap targets,
> a glitchy pull-to-refresh, and questioned the SwiftUI/VM architecture.
>
> **Execution rules for this phase**
> - Each task is sized for a single **Sonnet 5 subagent** (`ios-engineer`).
> - Every task is **TDD** (`/tdd`): write a failing test first where the logic is
>   pure/testable, then implement. UI-only tasks add a `#Preview` + a build-green
>   check instead of an XCTest.
> - Keep the package `swift test` green and both app targets building after every task.
> - One task = one commit. The orchestrator reviews each subagent commit before
>   dispatching the next dependent task.
> - Decisions locked in the 2026-07-09 grill are recorded inline per block.

### Block A — Logging (LLM-debuggable). Do first; everything else logs through it.
Grill decision: keep the `AppLogger`/`LoggerGroup` sink abstraction; add a filterable
Xcode-console sink **and** an exportable NDJSON file sink so an LLM can read logs.

- [x] **A1 — `ConsoleLogSink`** (pure, TDD) (2026-07-09)
      New `Diagnostics/ConsoleLogSink.swift` in `SpottersaurusKit`. Conforms to
      `AppLogger`; formats `"[\(level)][\(category)] \(message)"` and prints to
      stdout so Xcode's console filter box matches on `[motion]` etc. Test: inject a
      capture closure (make the print target injectable) and assert the formatted
      line for each level/category. Done-when: unit test green, sink formats exactly.
- [x] **A2 — `FileLogSink` NDJSON ring buffer** (actor, TDD) (2026-07-09)
      New `Diagnostics/FileLogSink.swift`. Sendable `actor` appending one JSON object
      per line (`ts` ISO8601, `level`, `category`, `target`, `message`) to a file in
      the shared App Group container (`group.amadeu.dev.Spottersaurus`). Ring-cap by
      byte size (rotate/truncate oldest). Expose async `exportURL()` / `readAll()`.
      Test against a temp dir: append N lines → assert NDJSON parses, cap trims oldest,
      concurrent appends don't interleave. Done-when: tests green.
- [x] **A3 — Wire sinks into `LoggerGroup`** (TDD-light) (2026-07-09)
      Extend `LoggerGroup.iPhone` / `.watch` to fan out to `OSLogLogger` +
      `ConsoleLogSink` + `FileLogSink` (shared file path per target, `target` field =
      `"iphone"`/`"watch"`). Test: a `LoggerGroup` with spy sinks forwards to all.
      Done-when: both targets build, existing log calls now hit all three sinks.
- [x] **A4 — In-app log viewer + export** (iPhone UI, `#Preview`) (2026-07-09)
      New debug screen (reachable from a Settings/Debug entry) listing recent NDJSON
      lines with a category filter, plus a `ShareLink`/share sheet exporting the log
      file. `#Preview` with seeded lines. Done-when: builds, preview renders, export
      produces the file. (No XCTest; UI-only.)

### Block B — Persistence truth (#1). Depends on A3.
Grill decision: log the winning store tier; if it lands **inMemory**, show a
non-dismissable "Data is NOT being saved" banner. Local fallback logs but runs normal.

- [x] **B1 — Store tier is observable + logged** (TDD) (2026-07-09)
      Refactor `SpottersaurusApp.makeContainer()` to return the container **and** a
      `StoreTier` (`.cloudKit`/`.local`/`.inMemory`); log the winner under
      `.persistence`. Put `StoreTier` + the selection logic in `SpottersaurusKit`
      (pure, injectable failing-factory) so it's testable without real CloudKit.
      Test: forced cloudKit failure → `.local`; both fail → `.inMemory`, each logged.
      Done-when: tests green, app compiles with the new return shape.
      <!-- Added `StoreTier` + `resolveModelContainer(makeContainer:logger:)` in
           `SpottersaurusSchema.swift` (SpottersaurusKit): runs the same
           cloudKit → local → inMemory ladder with an injected factory closure,
           logs the winning tier + each caught fallback error under
           `.persistence`, returns `(container, tier)`. `SpottersaurusApp` now
           calls it with the real `makeModelContainer` + `LoggerGroup.iPhone`
           and stores `let storeTier: StoreTier` for B2. New
           `StoreTierTests.swift` (3 tests) covers cloudKit success, cloudKit→
           local fallback, and cloudKit+local→inMemory fallback via a spy
           logger. -->
- [x] **B2 — inMemory warning banner** (iPhone UI, `#Preview`) (2026-07-09)
      When `StoreTier == .inMemory`, overlay a persistent, non-dismissable banner
      ("Data is NOT being saved — storage unavailable"). `#Preview` both states.
      Done-when: builds, preview shows banner only for inMemory.
      <!-- New `Features/Debug/StoreHealthBanner.swift`: renders nothing for
           `.cloudKit`/`.local`, an alert-tinted, non-dismissable top banner for
           `.inMemory`. `ContentView` now takes `storeTier: StoreTier` (defaulted
           to `.local`) and overlays the banner via `.overlay(alignment: .top)`;
           `SpottersaurusApp` passes its resolved `storeTier` through. Two
           `#Preview`s cover both states. -->

### Block C — HealthKit authorization (#3/#4). The core sync bug.
Grill decision: Watch requests `read: heartRate`, `share: workout (+ activeEnergy)`
on **first arm**, asked once. No auth today → HR empty + nothing written to Apple Health.

- [x] **C1 — `HealthKitAuthorizing` abstraction** (TDD) (2026-07-09)
      Protocol wrapping `HKHealthStore.requestAuthorization(toShare:read:)` +
      status check, with the concrete type list (share: `workout`, `activeEnergyBurned`;
      read: `heartRate`). Real impl + a fake for tests. Test the fake records requested
      types + gates "ask once". Done-when: tests green.
      <!-- Protocol `HealthKitAuthorizing` + `HealthAuthorizationStatus` (no
           HealthKit import — HealthKit has no macOS availability, and the
           package's tests run headless on macOS per Package.swift) live in
           SpottersaurusKit/HealthKit/HealthKitAuthorizing.swift, so they're
           reachable from package tests (no Watch test target exists). The
           concrete `HKHealthStore`-backed `HealthKitAuthorizer` actor (share:
           workoutType + activeEnergyBurned; read: heartRate; "ask once" gated
           via UserDefaults) lives next to the adapter in
           `Spottersaurus Watch App/Features/LiveSet/HealthKitAuthorizer.swift`.
           New `HealthKitAuthorizingTests.swift` (3 tests) + a `FakeHealthKitAuthorizer`
           actor assert the gate collapses two requests into one and that a
           throwing/denied request still lets the caller proceed without
           re-attempting on a later arm. Not wired into
           `WatchWorkoutSessionAdapter` yet (C2). -->
- [x] **C2 — Request auth on first arm** (TDD-light + on-device note) (2026-07-09)
      In `WatchWorkoutSessionAdapter.start`, call the authorizer **before**
      `beginCollection`, gated so it prompts once. Log outcome under `.workout`.
      Test: fake authorizer is invoked once across two arms; start still proceeds when
      denied (existing manual fallback). Done-when: tests green; leave an on-device
      verify checkbox.
      <!-- `WatchWorkoutSessionAdapter` now takes an injected `authorizer: any
           HealthKitAuthorizing` (default `HealthKitAuthorizer()`); `start(...)`
           awaits `authorizer.requestAuthorization()` + logs the resulting
           `authorizationStatusForHeartRate()` under `.workout` before building
           the `HKWorkoutConfiguration`/`startActivity`/`beginCollection`. A
           throw is caught and logged as a warning, never aborts the set —
           manual/dev fallback keeps working. No new gate added; the existing
           `HealthKitAuthorizer` ask-once (UserDefaults-backed) gate is reused
           as-is per C1. No Watch test target exists (confirmed again), so the
           gate/no-double-request/proceed-on-deny behavior is covered by the
           package-level `HealthKitAuthorizingTests` (C1, unchanged, still
           green) rather than a new Watch-target XCTest.
           [ ] ON-DEVICE VERIFY: pair a real Watch and confirm the system
           HealthKit prompt actually appears on first arm, HR reads flow into
           the live set, and the finished workout lands in Apple Health
           (Simulator cannot show or authorize the real HK permission sheet). -->
- [x] **C3 — Surface auth state on Watch** (Watch UI, `#Preview`) (2026-07-09)
      Show a compact indicator when HR auth is denied/undetermined so the user knows
      why HR is blank. `#Preview` the states. Done-when: builds, preview renders.
      <!-- `LiveSetViewModel` gained a `private(set) var hrAuthStatus:
           HealthAuthorizationStatus` (defaults `.notDetermined`) plus
           `refreshHRAuthStatus(using:) async`, which is the only way to set
           it — read-only from the UI's perspective. `WatchLiveSessionCoordinator`
           now takes an injectable `authorizer: any HealthKitAuthorizing`
           (default `HealthKitAuthorizer()`, shared with the
           `WatchWorkoutSessionAdapter` it constructs) and exposes
           `refreshHRAuthStatus(viewModel:)`, called from `LiveSetView.onAppear`
           and again internally after `workoutAdapter.start` resolves
           (success or failure) so a mid-arm permission grant/denial is
           picked up. New `Spottersaurus Watch App/Components/HRAuthIndicatorView.swift`
           renders nothing when `.sharingAuthorized`, else a compact
           heart.slash caution chip ("HR not authorized" / "Enable HR in
           Settings"); placed in `LiveSetView` directly under
           `LiveSetHeaderView`, above the rep gauge/metrics grid so it
           doesn't disturb the RACK IT overlay or existing layout. Three
           `#Preview`s cover all three statuses. No Watch test target exists
           (confirmed again per C1/C2), so this is Watch-UI-only; package
           tests (84 XCTest + 18 Swift Testing, 0 failures) are unaffected. -->

### Block D — Connection visibility (#2). Depends on A3.
Grill decision: WCSession state exists but is only logged; surface it reactively.

- [x] **D1 — `PhoneWatchSessionMonitor` exposes WCSession state** (TDD-light) (2026-07-09)
      Add `@Observable` fields for `activationState`, `isReachable`, `isPaired`,
      `isWatchAppInstalled`; update them from the iOS `WatchLink` delegate callbacks.
      Test the reducer that maps a session-state snapshot → a `ConnectionStatus` enum
      (pure). Done-when: test green, monitor updates on delegate events.
      <!-- Added `ConnectionStatus` (pure enum + `resolve` reducer) to
           SpottersaurusKit/Sync, table-tested in ConnectionStatusTests (7
           cases). `PhoneWatchSessionMonitor` gained isReachable/isPaired/
           isWatchAppInstalled/activationState + computed `connectionStatus`
           and `updateSessionState(...)`. `WatchLink` pushes snapshots from
           activationDidCompleteWith, the new sessionReachabilityDidChange,
           and both send() paths. -->
- [x] **D2 — Connection status chip** (iPhone UI, `#Preview`) (2026-07-09)
      Small reusable chip (connected / unreachable / not paired / app not installed),
      shown on Today and reused inside `LiveWatchStatusCardView`. `#Preview` each state.
      Done-when: builds, previews render, Today shows live status.
      <!-- New `Spottersaurus/Components/WatchConnectionChip.swift`: takes a
           `ConnectionStatus`, renders an icon+label capsule pill tinted per
           state (green connected, amber unreachable/app-not-installed, gray
           notPaired/inactive). `TodayView` shows it near the header, driven
           reactively by `PhoneWatchSessionMonitor.shared.connectionStatus`
           (`@Observable`); `LiveWatchStatusCardView` gained a
           `connectionStatus` param (default `.inactive`) and now renders the
           same chip in its header instead of the old ad-hoc timestamp/dot,
           wired from both `TodayView` and `ReviewView`. One `#Preview`
           renders all `ConnectionStatus.allCases`. -->
- [x] **D3 — Phone-reachability chip on Watch** (Watch UI, `#Preview`) (2026-07-09)
      Mirror a compact reachability chip on the Watch root using
      `WatchPlannedSessionStore` session state. `#Preview` states. Done-when: builds.
      <!-- `WatchPlannedSessionStore` is now `@Observable`, tracking
           `isReachable`/`activationState` (updated from
           `activationDidCompleteWith` + a new `sessionReachabilityDidChange`,
           hopping to `@MainActor`) and exposing `connectionStatus` via the
           shared `ConnectionStatus.resolve` reducer with `isPaired: true,
           isWatchAppInstalled: true` (watchOS can't observe those flags — see
           doc comment). New `Spottersaurus Watch App/Components/
           PhoneConnectionChip.swift` mirrors `WatchConnectionChip`'s look
           ("iPhone connected"/green, "iPhone unreachable"/amber,
           "Connecting…"/gray) with 4 `#Preview`s. Wired into
           `LiveSetView` above `LiveSetHeaderView` (only in the non-overlay
           branch, so it never competes with the RACK IT overlay or metrics
           grid). -->

### Block E — Watch real-vs-mocked (#5/#6). Depends on C2.
Grill decision: real motion/HR pipeline is primary; move manual +rep/flag behind a
`DEBUG` dev panel; **`rackIt` stays always-available** (safety bail). Surface live
pipeline telemetry so it's not a black box.

- [x] **E1 — Gate manual controls behind DEBUG dev panel** (Watch UI) (2026-07-09)
      In `LiveSetControlsView`, keep only Arm/Rack (+ always-visible `rackIt` bail) for
      release; move `completeRep`/`flagGrinding` into a `#if DEBUG` hidden dev panel
      (e.g. long-press to reveal). Auto-detection drives reps in release. Done-when:
      release build hides manual rep/flag; DEBUG shows them; `rackIt` always present.
      <!-- `.armed`/`.repping` now always renders a prominent alert-tinted
           "RACK IT" bail (hand.raised.fill, 44pt) above the existing "Rack"
           button — never gated. `completeRep`/`flagGrinding` moved into a
           `#if DEBUG`-only collapsed "DEBUG panel" disclosure (tap to reveal,
           starts hidden) so a Release build never shows manual rep/grind
           taps; auto-detection is the only rep source there. Added 3
           `#Preview`s (idle/armed/resting). Verified both
           `xcodebuild -scheme 'Spottersaurus Watch App' -configuration
           Debug|Release -destination 'generic/platform=watchOS Simulator'
           build` succeed with the `#if DEBUG` compiling both ways; package
           `swift test` unaffected (84 XCTest + 25 Swift Testing, 0
           failures). No Watch test target exists, per Block E scope this is
           Watch-UI-only. -->
- [x] **E2 — Live pipeline telemetry readout** (Watch UI, `#Preview`) (2026-07-09)
      Small readout: sensor running?, samples/sec, HR flowing?, last-sample age — from
      the live coordinator/view model. `#Preview` with seeded telemetry. Done-when:
      builds, preview renders, values update while armed.
      <!-- New `LivePipelineTelemetry` (SpottersaurusKit/Detection) is a pure
           Sendable/Equatable snapshot + `static func make(motionSampleTimestamps:
           hrSampleTimestamps:now:sensorRunning:window:hrWindow:)`, TDD'd first
           (10 Swift Testing cases: rate over trailing window, samples outside
           the window excluded, nil age with no samples, newest-timestamp age
           regardless of array order, HR flowing/stale/never-arrived, sensorRunning
           passthrough, `.idle` default). `LiveSetViewModel` now records wall-clock
           (not set-relative) motion/HR ingest timestamps in a small trailing
           buffer (2s retention, trimmed on every ingest) and exposes
           `telemetry(sensorRunning:now:) -> LivePipelineTelemetry`; sensorRunning
           itself comes from the caller since the view model doesn't own the
           motion adapter. `WatchLiveSessionCoordinator` gained `isMotionRunning`
           (motion-adapter-only, distinct from the combined HR+motion `isRunning`).
           New `Components/PipelineTelemetryView.swift`: compact single-row
           capsule (sensor ●/○ + "xx/s", HR ●/○, last-sample age), 3 `#Preview`s
           (alive/stalled/idle). Wired into `LiveSetView` as a subtle always-on
           micro-readout shown only while `.armed`/`.repping` (least intrusive —
           no card, no DEBUG gate, hidden pre-arm/post-rack); a dedicated 1s timer
           tick (`telemetryNow`) refreshes it so staleness visibly increases even
           with no new samples. `swift test`: 84 XCTest + 35 Swift Testing (10
           new), 0 failures. `xcodebuild -scheme 'Spottersaurus Watch App'
           -destination 'generic/platform=watchOS Simulator' build`: BUILD
           SUCCEEDED. -->

### Block F — Architecture + reactivity (#8/#9). Independent of A–E.
Grill decision: convert list VMs to `@Observable` classes owning derived state,
**hybrid** — the view keeps a light `@Query` and pipes results into the VM via
`.onChange`, preserving CloudKit reactivity while making VMs testable. Remove the
no-op `.refreshable`. Add `#Preview` everywhere.

- [x] **F1 — `HistoryViewModel` → @Observable hybrid** (TDD) (2026-07-09)
      Convert to `@Observable final class`; it accepts `[WorkoutSession]` and exposes
      sorted/derived output. `HistoryView` keeps `@Query`, feeds the VM via
      `.onChange(of: sessions)` + initial load. Test derived ordering/summary output.
      Done-when: test green, list still updates on data change.
      <!-- `HistoryViewModel` is now a `@MainActor @Observable final class` owning
           `private(set) var sessions: [WorkoutSession]`, populated only via
           `update(with:)` (sorts newest-first). All prior pure formatting helpers
           (sessionTitle/Subtitle, setTitle/Subtitle, velocitySummary, orderedSets)
           kept as methods, unchanged behavior; `refreshSavedSessionCount` left in
           place per F5. `HistoryView` now holds `@State private var viewModel =
           HistoryViewModel()`, keeps its `@Query private var sessions`, and feeds
           the VM via `.onChange(of: sessions, initial: true)`; rendering reads
           from `viewModel.sessions`, so the list still updates live on
           SwiftData/CloudKit changes. `HistorySessionRowView`/`SessionDetailView`/
           `SessionSummaryCardView`/`CompletedSetDetailCardView` needed no changes
           (still take/call the VM). TDD: an app-target test target
           (`SpottersaurusTests`, Swift Testing, `PBXFileSystemSynchronizedRootGroup`
           — confirmed it can `@testable import Spottersaurus` and already had a
           working placeholder test) exists, so no package-function detour was
           needed; new `SpottersaurusTests/HistoryViewModelTests.swift` (5 tests)
           covers newest-first ordering, `update` replacing prior derived state,
           and title/subtitle/velocity formatting (built from the same
           `.formatted` calls to stay locale-agnostic, since the sim run under a
           comma-decimal locale). Package `swift test`: 84 XCTest + 35 Swift
           Testing, 0 failures (unaffected — History lives in the app target).
           `xcodebuild -scheme Spottersaurus -destination 'platform=iOS Simulator,
           name=iPhone 17' build`: BUILD SUCCEEDED. -->
- [x] **F2 — `AnalyticsViewModel` → @Observable hybrid** (TDD) (2026-07-09)
      Same pattern; fold the throwaway `HistoryViewModel()` usage out. Test the
      derived analytics inputs. Done-when: test green, charts still render.
      <!-- `AnalyticsViewModel` is now a `@MainActor @Observable final class`
           owning `private(set) var records: [SetRecord]`, populated only via
           `update(with:)` (same mapping WorkoutSession→SetRecord as before,
           unchanged behavior). Its chart-facing methods (`e1RMTrend`,
           `tonnageSeries`, `velocityLoadPoints`, `spotterFrequency`,
           `totalTonnage`, `bestEstimatedOneRepMax`) now read the owned
           `records` instead of taking a `from:` parameter — the pure
           `PerformanceAnalytics` funcs are unchanged/reused, so chart output
           is identical for identical input sessions. `AnalyticsView` now
           holds `@State private var viewModel = AnalyticsViewModel()`, keeps
           its `@Query private var sessions`, and feeds the VM via
           `.onChange(of: sessions, initial: true)`; charts render from
           `viewModel.records`/the above methods. Removed the throwaway
           `HistoryViewModel().refreshSavedSessionCount(...)` call (and its
           `.refreshable`/`modelContext` plumbing) per F2's requirement — the
           `.refreshable` modifier itself is left for F5 to delete elsewhere
           (History still has one). TDD: new
           `SpottersaurusTests/AnalyticsViewModelTests.swift` (4 tests) covers
           `update` populating/replacing derived `SetRecord`s, e1RM trend
           output matching `PerformanceAnalytics.e1RMTrend` exactly for owned
           records, and locale-agnostic tonnage/best-e1RM formatting (built
           from the same `.formatted` calls, since the sim runs a
           comma-decimal locale). Package `swift test`: 84 XCTest + 35 Swift
           Testing, 0 failures (unaffected — Analytics lives in the app
           target). App-target tests
           (`-only-testing:SpottersaurusTests`): 10 tests, 0 failures.
           `xcodebuild -scheme Spottersaurus -destination 'platform=iOS
           Simulator,name=iPhone 17' build`: BUILD SUCCEEDED. -->
- [x] **F3 — `MaxesViewModel` → @Observable hybrid** (TDD) (2026-07-09)
      Same pattern for the Maxes editor. Test derived output. Done-when: green.
      <!-- `MaxesViewModel` is now a `@MainActor @Observable final class` owning
           `private(set) var competitionMaxes: [UserMaxes]`, populated only via
           `update(with:)` (filters + orders to squat → bench → deadlift, same
           as the prior stateless `competitionMaxes(from:)` helper).
           `ensureCompetitionMaxesExist(in:existingMaxes:)` keeps its exact
           prior signature/behavior (a side effect on `modelContext`, not
           derived state — still called from `.onAppear`). `MaxesView` now
           holds `@State private var viewModel = MaxesViewModel()`, keeps its
           `@Query private var maxes`, and feeds the VM via `.onChange(of:
           maxes, initial: true)`; the row `ForEach` reads
           `viewModel.competitionMaxes`. Debug Logs toolbar entry (A4)
           untouched; edit flows (`MaxesRow`'s `@Bindable` Steppers) untouched
           — they bind directly to the `UserMaxes` model objects still owned
           by SwiftData. TDD: new `SpottersaurusTests/MaxesViewModelTests.swift`
           (5 tests) covers competition-order sorting regardless of input
           order, exclusion of `.accessory`, omission of missing competition
           lifts, `update` replacing prior derived state, and
           `ensureCompetitionMaxesExist` inserting only the missing lifts
           (in-memory `ModelContainer`) while leaving existing records
           untouched. Package `swift test`: 84 XCTest + 35 Swift Testing, 0
           failures (unaffected — Maxes lives in the app target). App-target
           tests (`-only-testing:SpottersaurusTests`): 15 tests, 0 failures.
           `xcodebuild -scheme Spottersaurus -destination 'platform=iOS
           Simulator,name=iPhone 17' build`: BUILD SUCCEEDED. -->
- [x] **F4 — `ProgramsViewModel` → @Observable hybrid** (TDD) (2026-07-09)
      Same pattern for Programs list. Test derived output. Done-when: green.
      <!-- `ProgramsViewModel` is now a `@MainActor @Observable final class`
           owning `private(set) var programs: [Program]`, populated only via
           `update(with:)` (sorts newest-first, same as the prior stateless
           `sortedPrograms(_:)` helper). `loadFiveThreeOne`/
           `loadLinearProgression`/`createProgram` keep their exact prior
           signatures/behavior (side effects on `modelContext`, not derived
           state). `deletePrograms(at:in:)` now indexes into the owned sorted
           `programs` array instead of re-sorting a passed-in `programs` param,
           matching the order `ProgramsView`'s `ForEach` renders. `ProgramsView`
           now holds `@State private var viewModel = ProgramsViewModel()`,
           keeps its `@Query private var programs`/`@Query private var maxes`,
           and feeds the VM via `.onChange(of: programs, initial: true)`; the
           row `ForEach` reads `viewModel.programs`. Preset-insert buttons,
           delete swipe, builder sheet, and `ProgramDetailView` navigation
           (load resolution stays in the separate `PlannedSetRow` component,
           untouched — out of scope for the list VM) all preserved unchanged.
           TDD: new `SpottersaurusTests/ProgramsViewModelTests.swift` (4 tests)
           covers newest-first sorting regardless of input order, `update`
           replacing prior derived state, `deletePrograms` removing from the
           owned sorted order (in-memory `ModelContainer`), and
           `loadFiveThreeOne` inserting a program with the `.fivethreeone`
           rule. Package `swift test`: 84 XCTest + 35 Swift Testing, 0
           failures (unaffected — Programs list VM lives in the app target). App-target
           tests (`-only-testing:SpottersaurusTests`): 19 tests, 0 failures.
           `xcodebuild -scheme Spottersaurus -destination 'platform=iOS
           Simulator,name=iPhone 17' build`: BUILD SUCCEEDED. -->
- [x] **F5 — Remove no-op `.refreshable`** (fixes #8 by deletion) (2026-07-09)
      Delete `.refreshable` from `HistoryView` + `AnalyticsView` (data is live via
      `@Query`); drop the now-unused `refreshSavedSessionCount` if nothing else calls
      it. Done-when: builds, no pull-to-refresh jank, no dead code.
      <!-- `AnalyticsView` was already clean (F2 removed its `.refreshable`/throwaway
           VM call). Removed `HistoryView`'s `.refreshable { viewModel
           .refreshSavedSessionCount(in: modelContext) }` and the now-unused
           `@Environment(\.modelContext)` (nothing else in the view read it). Grepped
           the whole repo for `refreshSavedSessionCount`: only the
           `HistoryViewModel` definition and that one call site existed, so deleted
           the method too, then dropped the now-unused `import SwiftData` from
           `HistoryViewModel.swift` (it only imported it for `ModelContext`/
           `FetchDescriptor`, both gone). `@Query` reactivity is unchanged and
           remains the sole live-update mechanism for both screens. Package
           `swift test`: 84 XCTest + 35 Swift Testing, 0 failures. App-target tests
           (`-only-testing:SpottersaurusTests`): 19 tests, 0 failures (no test
           referenced the removed method). `xcodebuild -scheme Spottersaurus
           -destination 'platform=iOS Simulator,name=iPhone 17' build`: BUILD
           SUCCEEDED. -->
- [x] **F6 — `#Preview` sweep (iPhone)** (2026-07-09)
      Add `#Preview` (using `makeModelContainer(inMemory:true)` + minimal seed) to
      Today, Programs, ProgramDetail, builders, Maxes, Review, SessionDetail, and the
      components missing one. Done-when: every iPhone view has a rendering preview.
      <!-- New `#if DEBUG` `PreviewSupport/PreviewSeedData.swift`: a small
           `PreviewSeed` enum (maxes/program/workoutSession + insertStandardSeed/
           seededContainer helpers) shared across previews so feature files don't
           each hand-roll domain objects. Added `#Preview`s to every iPhone
           feature view and component that lacked one: Today (TodayView,
           TodaySessionCard), Programs (ProgramsView, ProgramDetailView,
           ProgramBuilderView, ProgramDayBuilderView — `@Previewable @State`
           binding, PlannedSetBuilderView — same), Maxes (MaxesView), Review
           (ReviewView), History (SessionDetailView + all 7 Components:
           SpotterEventsView, RepMetricRowView, FlowLayout, HistorySessionRowView,
           HistoryMetricLineView, SessionSummaryCardView,
           CompletedSetDetailCardView), Analytics (all 8 Components:
           AnalyticsChartCardView, AnalyticsMetricCardView, VelocityLoadChartView,
           SpotterFrequencyChartView, AnalyticsSummaryGridView,
           AnalyticsEmptyChartView, E1RMTrendChartView, TonnageChartView), and
           top-level Components (PlannedSetRow, LiveWatchStatusCardView,
           MetricLine, EmptyPlannerStateView — WatchConnectionChip already had
           one). `SessionDetailView.swift`, `ProgramDetailView.swift`, and
           `ReviewView.swift` needed a new `import SwiftData` to call
           `.modelContainer(...)` in their previews (production code/behavior
           unchanged). No production view logic changed. Package `swift test`:
           84 XCTest + 35 Swift Testing, 0 failures (unaffected). App-target
           tests (`-only-testing:SpottersaurusTests`): 19 tests, 0 failures.
           `xcodebuild -scheme Spottersaurus -destination 'platform=iOS
           Simulator,name=iPhone 17' build`: BUILD SUCCEEDED. -->

- [x] **F7 — `#Preview` sweep (Watch)** (2026-07-09)
      Add `#Preview` to the Watch feature views + components missing one (LiveSet
      panels, controls, overlays, metric tiles). Done-when: every Watch view previews.
      <!-- Added `#Preview`s to every Watch Component that lacked one:
           LiveSetCalibrationPanelView (idle/collecting), LiveSetCrownModeControlView
           (load/reps selected), LiveSetHeaderView (optimal/grinding/rackIt tones),
           LiveSetMetricTile (with/without unit), LiveSetMetricsGridView,
           LiveSetRepGaugeView (optimal/grinding/rackIt), RackItOverlayView
           (alerting). LiveSetView, LiveSetControlsView, HRAuthIndicatorView,
           PhoneConnectionChip, and PipelineTelemetryView already had previews
           from earlier phases. LiveSetTone (enum) and LiveSetCalibrationState
           (enum) are pure logic, not Views — skipped per scope. No production
           view logic changed; all no-op closures / representative enum cases
           per house style. Package `swift test`: 84 XCTest + 35 Swift Testing,
           0 failures (unaffected). `xcodebuild -scheme 'Spottersaurus Watch App'
           -destination 'generic/platform=watchOS Simulator' build`: BUILD
           SUCCEEDED. -->

### Block G — Touch targets (#7). Independent.
- [x] **G1 — 44pt touch-target audit (Watch)** (2026-07-09)
      Audit crown-mode, header, and calibration-panel controls to ≥44pt hit targets
      (liveButtons already comply). Done-when: all interactive Watch controls ≥44pt.
      <!-- Audited every `Button` under `Spottersaurus Watch App/` (grep confirmed
           no other `Button`/`.onTapGesture`/`Toggle`/`Stepper`/`Picker` controls
           exist outside the ones already known). `LiveSetCrownModeControlView`'s
           two mode-toggle icon buttons and `LiveSetHeaderView` (no buttons, just a
           status glyph) were already compliant. Found two real gaps:
           `LiveSetControlsView`'s "Rest Done" button (`.racked`/`.resting` state)
           had no `.frame` at all, unlike its sibling Arm/Rack/RACK IT buttons — now
           `.frame(maxWidth: .infinity, minHeight: 44)`. `LiveSetCalibrationPanelView`'s
           "Warmup"/"Restart" and "Save" buttons had no explicit hit-target sizing;
           now each label carries `.frame(maxWidth: .infinity, minHeight: 44)`,
           splitting the HStack evenly while guaranteeing ≥44pt height. No
           behavior/callback changes; `RackItOverlayView`'s "Resolved" button was
           already `.frame(minWidth: 96, minHeight: 44)`. Package `swift test`: 35
           Swift Testing tests, 0 failures. `xcodebuild -scheme 'Spottersaurus
           Watch App' -destination 'generic/platform=watchOS Simulator' build`:
           BUILD SUCCEEDED. -->

### Phase 0 — dependency order for dispatch
`A1 → A2 → A3` (then `A4`, `B1→B2`, `D1→D2/D3` can run once A3 lands) ·
`C1 → C2 → C3` · `E1/E2` after `C2` · `F1–F7` and `G1` are independent and can run
in parallel with the rest. Review each subagent commit before dispatching dependents.

---

## Phase 0.1 — UX & Health Integration

> Inserted 2026-07-09, after Phase 0. Origin: user wants the Review tab cleaned up,
> a working (real) pull-to-refresh, an iPhone-side Apple Health sync, and a Profile
> tab; plus a Watch-embed fix surfaced by live logs (`isWatchAppInstalled=false`).
>
> **Execution rules** (same as Phase 0): one Sonnet 5 subagent per task, TDD where
> logic is pure (`/tdd`), `#Preview` + build-green for UI-only tasks, one task = one
> commit, orchestrator reviews each commit before dispatching dependents. Keep
> package `swift test` + both target builds green.
>
> **Grill decisions (2026-07-09):** live-tick card → Today (session-active only) ·
> Apple Health = authorize + **import** (read-only: body weight + recent
> functional-strength workouts; no writes back this round) · Profile tab **absorbs**
> the Maxes tab · pull-to-refresh does real async work (CloudKit remote fetch +
> Health import).

### Block W — Watch embed (unblocks all Watch↔iPhone). DONE.
- [x] **W1 — Embed Watch app into iOS app** (2026-07-09)
      <!-- iOS app target had no "Embed Watch Content" copy-files phase, so the
           companion never installed (isWatchAppInstalled=false → all iPhone→Watch
           sends failed). Added the phase + target dependency (manual Xcode), then
           normalized via the xcodeproj gem: CodeSignOnCopy + buildActionMask
           2147483647. Verified Spottersaurus.app/Watch/ contains the watch app
           after a plain iOS build. Commit e8c0e54. On-device: install by running
           the iPhone scheme (not the Watch scheme). -->

### Block R — Move the live-tick card off Review
- [x] **R1 — Remove `LiveWatchStatusCardView` from `ReviewView`** (iOS UI) (2026-07-09)
      Review becomes just the History/Analytics segmented picker. Drop the card +
      the now-unused `watchMonitor` wiring in `ReviewView` if nothing else needs it.
      Keep the `#Preview`. Done-when: builds, Review shows no live card.
- [x] **R2 — Show live-tick card on `TodayView`, session-active only** (iOS UI, `#Preview`) (2026-07-09)
      Render `LiveWatchStatusCardView` on Today ONLY while a Watch session is active
      — gate on `PhoneWatchSessionMonitor.shared.lastTick` recency (e.g. a tick within
      the last N seconds) so it appears mid-set and hides when idle. `#Preview` both
      states (active tick vs none). Done-when: builds, card shows only with a recent tick.
      <!-- `TodayView` gained `static let liveSessionWindow: TimeInterval = 10` +
           a private `isLiveSessionActive(at:)` helper (`lastTick != nil` AND
           `now.timeIntervalSince(lastTickReceivedAt) <= liveSessionWindow`).
           The card is wrapped in `TimelineView(.periodic(from: .now, by: 1))`
           purely so the gate re-evaluates once a second and the card
           disappears shortly after ticks stop even with no new data arriving
           — placed right under the `WatchConnectionChip`, above the planned
           session card, so it's visible mid-set without disturbing the rest
           of Today. Two new `#Preview`s ("Watch session live" / "Watch
           session idle") seed `PhoneWatchSessionMonitor.shared` directly.
           Package `swift test`: 84 XCTest + 35 Swift Testing, 0 failures.
           `xcodebuild -scheme Spottersaurus -destination 'platform=iOS
           Simulator,name=iPhone 17' build`: BUILD SUCCEEDED. -->

### Block H — Apple Health import (iPhone). Depends on nothing; H2 after H1.
- [x] **H1 — iPhone `HealthKitAuthorizing` impl** (TDD via package fake) (2026-07-09)
      Add an iOS-target concrete `HealthKitAuthorizing` (the protocol is already in
      `SpottersaurusKit`; the Watch has its own impl). Request read: `workout`,
      `bodyMass`, `heartRate`. Reuse the package `HealthAuthorizationStatus`. Gate
      ask-once (UserDefaults) like the Watch impl. Log under a NEW `.health`
      category (add `health` to `AppLogCategory`). Test the gate/ask-once via the
      existing package `FakeHealthKitAuthorizer` pattern. Done-when: tests green, iOS builds.
      <!-- Added `health` to `AppLogCategory` (package). New
           `Spottersaurus/Features/Health/PhoneHealthKitAuthorizer.swift`: actor
           conforming to `HealthKitAuthorizing`, read-only (workout, bodyMass,
           heartRate), ask-once gate via a distinct UserDefaults key
           (`PhoneHealthKitAuthorizer.hasRequestedAuthorization`), logs outcome
           under `.health` via `LoggerGroup.iPhone`. Not wired into any view
           (H3/P1 do that). `swift test`: 85 XCTests + 35 Swift Testing tests
           green. `xcodebuild -scheme Spottersaurus -destination 'platform=iOS
           Simulator,name=iPhone 17' build`: BUILD SUCCEEDED. `-only-testing:
           SpottersaurusTests`: TEST SUCCEEDED (19 cases). -->
- [x] **H2 — `HealthImporter` (read HKWorkout + bodyMass → app models)** (TDD pure mapping) (2026-07-09)
      A service that queries recent `HKWorkout` (functionalStrengthTraining only) +
      most-recent `bodyMass` and maps them into app models. Split PURE mapping
      (HK-neutral value structs → domain models / dedupe by date+id) from the HK
      query (wrap the query behind a small protocol so the mapping is unit-tested
      without HealthKit). TDD the mapping in `SpottersaurusTests` or package. Idempotent
      (re-import doesn't duplicate). Done-when: mapping tests green, iOS builds.
      <!-- New `SpottersaurusKit/HealthKit/HealthDataReading.swift`: HK-neutral
           value types (`ImportedWorkoutActivity`, `ImportedWorkout`,
           `ImportedBodyWeight`), the `HealthDataReading` query protocol
           (`recentWorkouts(limit:)` / `latestBodyWeight()`), the pure
           `HealthWorkoutMapper.map(_:)` (filters to
           `.functionalStrengthTraining`, collapses duplicates by a dedupe key
           — HK UUID when present, else an ISO8601 start-date string — via a
           `Set<String>` seen-check, first-seen order preserved), the mapped
           `ImportedWorkoutSession` output type (shaped to match
           `WorkoutSession`'s `date`/`healthKitWorkoutUUID` fields so H3 can
           construct one directly — no `CompletedSet` since Health imports
           carry no reps/weight/velocity, per the task's "lightweight record"
           allowance; no new SwiftData model added), `HealthImportResult`, and
           the injectable `HealthImporter` (takes a `HealthDataReading`, reads
           workouts + body weight concurrently via `async let`, maps through
           `HealthWorkoutMapper`, returns the result — no persistence, that's
           H3). New `Spottersaurus/Features/Health/PhoneHealthDataReader.swift`:
           the real `HKHealthStore`-backed `HealthDataReading` conformer,
           querying `HKWorkout` via `HKSampleQueryDescriptor` filtered to
           `.functionalStrengthTraining` (newest first) and the most recent
           `HKQuantityType(.bodyMass)` sample, converting explicitly via
           `.gramUnit(with: .kilo)`; not wired into any service yet (H3 does
           that). TDD: new `HealthImporterTests.swift` (10 XCTest cases) covers
           in-batch dedupe by HK UUID and by start date when the UUID is
           missing, distinct start dates staying separate, non-functional-
           strength activities excluded, field-preserving mapping, empty input,
           `HealthImporter` returning mapped workouts + body weight, nil body
           weight when absent, `limit` respected, and reader-thrown errors
           propagating. Package `swift test`: 95 XCTest + 35 Swift Testing, 0
           failures. `xcodebuild -scheme Spottersaurus -destination
           'platform=iOS Simulator,name=iPhone 17' build`: BUILD SUCCEEDED.
           `-only-testing:SpottersaurusTests`: TEST SUCCEEDED (19 cases,
           unchanged — the pure mapping lives entirely in the package). -->
- [x] **H3 — Health sync service (`lastSyncedAt` + status)** (TDD-light) (2026-07-09)
      An `@Observable @MainActor` service tying H1 (auth) + H2 (import): `sync()` async
      that authorizes, imports, persists, stamps `lastSyncedAt`, exposes a status
      (`idle`/`syncing`/`synced(date)`/`failed`). Log each step under `.health`. Test
      the status state machine with fakes. Done-when: tests green, iOS builds.
      <!-- `Spottersaurus/Features/Health/HealthSyncService.swift` (@MainActor
           @Observable) ties H1 auth + H2 import: sync(context:) authorizes ->
           HealthImporter.importRecent() -> HealthSyncPersister.persist ->
           stamp lastSyncedAt (UserDefaults) + status idle/syncing/synced/failed.
           Never throws; failed status carries no partial persistence. New
           SpottersaurusKit/Persistence/HealthSyncPersister.swift upserts
           workouts by healthKitWorkoutUUID as .appleHealth history + single
           latest BodyWeightEntry (new @Model, registered in schema). SourceDevice
           gains .appleHealth. 5 Swift Testing cases via package fakes. Package
           swift test green (35). Commit 852f712. -->


### Block P — Profile tab (absorbs Maxes). Depends on H3.
- [ ] **P1 — `ProfileView`** (iOS UI, `#Preview`)
      New screen with sections: body info (body weight + units), the existing Maxes
      editor content (reuse `MaxesView`'s body/sections — extract if needed), a
      "Sync with Apple Health" button wired to the H3 service (shows status +
      last-synced time), and the Debug Logs entry (MOVED here from Maxes). `#Preview`
      with seeded data + each sync status. Done-when: builds, previews render, button
      triggers sync.
- [ ] **P2 — Swap Maxes tab → Profile tab** (iOS UI)
      `PlannerTabsView`: replace the Maxes tab with a Profile tab (person icon:
      `person.crop.circle`). Ensure `ensureCompetitionMaxesExist` still runs (move the
      call if it lived in Maxes/Profile). Tabs become Today · Programs · Review ·
      Profile. Done-when: builds, 4 tabs, Maxes content reachable inside Profile.

### Block X — Real pull-to-refresh
- [ ] **X1 — Async `.refreshable` (CloudKit fetch + Health import)** (iOS UI)
      Re-add `.refreshable` to History (and/or the Review container) as a REAL async
      closure that awaits: (a) a CloudKit remote-change fetch/nudge and (b) the H3
      Health sync. Genuine work → honest spinner + smooth animation. NOT the old
      synchronous no-op. Done-when: builds, pull-to-refresh runs real async work with
      a smooth spinner. Depends on H3.

### Phase 0.1 — dependency order for dispatch
`W1` (done) · `R1`, `R2` independent · `H1 → H2 → H3` · `P1 → P2` after `H3` ·
`X1` after `H3`. Review each subagent commit before dispatching dependents.

---

## Phase 0.2 — Live Session Surfaces & Multi-Set Execution

> Inserted 2026-07-09 from a `/grill-with-docs` session. Origin: user wants an
> Apple-Fitness-style experience — the iPhone changes to an in-workout screen
> when a set starts, a lock-screen Live Activity shows glanceable stats, and
> velocity feels real-time; the Watch↔iPhone mirror has a visible delay. Also
> surfaced: the Watch only ever runs the FIRST set of the day and falls back to
> a hardcoded bench @ 100 kg, so "everything is bench / same load". Decisions +
> constraints recorded in **`docs/adr/0001-live-session-surfaces-and-transport.md`**
> and the new glossary terms in `CONTEXT.md` (Live Session, In-Workout View,
> Session Override, Mean Concentric Velocity, Live Set Lifecycle Event).
>
> **Grill decisions (2026-07-09):**
> - Watch = the real-time instrument; iPhone + lock screen are glanceable, low-freq.
> - Velocity metric = **Mean Concentric Velocity per rep**, shown at rep completion.
> - Add explicit **Live Set Lifecycle Events** (`armed`/`ended`) to the stream.
> - Foreground transport = **coalesce-to-latest** (never drop the freshest tick).
> - Live Activity **starts foreground** (on Send-to-Watch); updates via
>   `activity.update` when reachable + opportunistic `transferUserInfo`
>   background-wakes; elapsed/rest via `Text(timerInterval:)`. **No APNs server
>   in v1.0.0** → few-second staleness while locked is accepted.
> - iPhone In-Workout View = app-wide, **dismissible** full-screen takeover,
>   lifecycle-managed. Replaces R3's "expand during a set" role.
> - Dynamic Island: **reps + Alert-Stage color** in compact/minimal; full metrics
>   in expanded + lock-screen card.
> - Watch AOD: calm static variant via `isLuminanceReduced`; alarm stays
>   haptic/audio (no forced full-brightness).
> - Live Session lifetime is **session-scoped** (spans sets + rests), 5-min
>   staleness timeout.
> - Multi-set: Watch runs the whole day, **manual arm per set**, next set shown
>   during rest; replace the bench-100 fallback with an honest "no session" state.
> - iPhone edit = ephemeral **Session Override** (does not mutate the Program).
>
> **Execution rules** (same as Phase 0): one Sonnet 5 subagent per task, TDD
> where logic is pure, `#Preview` + build-green for UI, one task = one commit,
> orchestrator reviews each commit before dispatching dependents.

### Block L — Live-session foundation (stream + transport + phone state)
- [ ] **L1 — Live Set Lifecycle Events** (TDD, package)
      Add `armed`(lift/target reps/weight/set index/set count) and `ended` signals
      to the Watch→phone stream (extend the envelope set in `Sync/`). Ticks carry
      running metrics + current Alert Stage + set N-of-M. Pure encode/decode +
      reducer tests. Done-when: package tests green.
- [ ] **L2 — Coalesce-to-latest transport** (TDD where pure) — depends on L1
      Rewrite `WatchPlannedSessionStore.send(liveTick:)`: keep the newest tick,
      send it when the in-flight send completes (no drop-on-in-flight), rep-
      completion ticks prioritized, ~2 s heartbeat, remove the 5 s hard backoff
      (small/adaptive instead). Extract the coalescing decision into a pure,
      testable type. Done-when: coalescer tests green, Watch builds.
- [ ] **L3 — `LiveSessionMonitor` (iPhone)** (TDD state machine) — depends on L1
      Session-scoped state machine (`idle→armed→active↔resting→ended`) fed by
      lifecycle events + ticks, with the 5-min staleness timeout; replaces the
      tick-recency heuristic in `PhoneWatchSessionMonitor`. Drives all iPhone
      surfaces. Test the state machine + timeout with injected time. Done-when:
      tests green, iOS builds.

### Block M — Multi-set Watch execution (the "everything is bench" fix)
- [ ] **M1 — Watch runs the whole day, manual arm per set** (TDD pure) — depends on L1
      Replace `currentPlannedSet()`'s `firstSet`-only + bench-100 fallback: track
      an ordered set cursor, advance on rack→rest→next (queued, **manual arm**),
      expose "Set N of M" + next-set prescription during rest. No planned session
      received → honest "no session sent" empty state, not a fake bench set.
      Extract the cursor/advancement as a pure Sendable type + tests. Done-when:
      advancement tests green, Watch builds, emits L1 `armed`/`ended` per session.
- [ ] **M2 — iPhone Session Override editor + Send** (TDD build, iOS UI) — depends on M1
      Tap today's session on Today → quick editor (per set: lift, target reps,
      weight, rest, AMRAP) → Send-to-Watch ships the adjusted
      `PlannedSessionEnvelope`. Ephemeral (does not mutate the Program). Test the
      override→envelope construction. `#Preview`. Done-when: tests green, edited
      session sends, Program unchanged.

### Block S — iPhone live surfaces
- [ ] **S1 — In-Workout View (app-wide dismissible takeover)** (iOS UI, `#Preview`) — depends on L3
      Full-screen cover presented from root on `armed`, dismissible with a
      "return to set" pill, auto-dismissed on session end. Big reps/target,
      Mean Concentric Velocity, HR, Alert-Stage banner (amber/red tint), rest
      ring, set N-of-M. `#Preview` idle/active/grinding/rackIt/resting. Done-when:
      builds, previews render, appears/updates/dismisses off `LiveSessionMonitor`.
- [ ] **R3 — Today collapsible card (idle/disconnected + reconnect)** (iOS UI, `#Preview`) — depends on L3
      Reconcile the earlier R3: Today shows a compact card when idle/Watch
      disconnected, with a reconnect affordance; the "expand during a set" role is
      handled by S1 (In-Workout View), not this card. `#Preview` states.
- [ ] **S2 — Live Activity (ActivityKit)** (iOS UI + new Widget Extension target) — depends on L3
      NEW Widget Extension target (manual Xcode/xcodeproj step — flag like the
      Watch embed). `ActivityAttributes` = static set identity (lift/target/weight/
      program-day); `ContentState` = reps/velocity/HR/Alert Stage/set N-of-M.
      Lock-screen card + Dynamic Island (compact = reps + Alert-Stage tint,
      minimal = reps, expanded = full metrics). Start foreground on Send-to-Watch;
      update via `activity.update` on reachable + `transferUserInfo` wakes;
      elapsed/rest via `Text(timerInterval:)`. `NSSupportsLiveActivitiesFrequent
      Updates` NOT required (no APNs). `#Preview` the widget states. Done-when:
      target builds, Activity starts/updates/ends over a real session.

### Block V — Watch always-on + velocity polish
- [ ] **V1 — Watch Always-On Display variant** (Watch UI, `#Preview`) — independent
      `isLuminanceReduced`-driven calm variant of `LiveSetView`: static reps/
      Alert-Stage/rest, freeze pulsing borders + velocity churn + telemetry.
      RACK IT stays haptic/audio (unchanged). `#Preview` luminance-reduced.
      Done-when: builds, AOD variant renders calm/static.
- [ ] **V2 — Mean Concentric Velocity readout crispness** (Watch UI) — independent
      Ensure the Watch surfaces the per-rep Mean Concentric Velocity clearly at
      rep completion (label it, `.monospacedDigit()`, no stale/flicker between
      reps). Small; verify against `LiveSetViewModel.velocityMS` = `rep.meanVelocityMS`.

### Phase 0.2 — dependency order for dispatch
`L1 → L2`, `L1 → L3`, `L1 → M1` · `M2` after `M1` · `S1`/`R3`/`S2` after `L3` ·
`V1`/`V2` independent. `S2` needs the new Widget Extension target created first.
Review each subagent commit before dispatching dependents.

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
- [x] Escalating alert: `.sensoryFeedback` haptics + audio cue + full-screen RACK IT (2026-07-08)
      <!-- Full-screen RACK IT overlay now pairs escalating watch haptics with
           a spoken "Rack it" cue through AVFoundation. Alert feedback is
           deduped per alert stage so repeated renders do not spam the wearer. -->
- [x] Rest timer ring + completion haptic (2026-07-08)
      <!-- Rack starts the injected rest window, ticks once per second through
           the pure lifecycle controller, updates the rest ring/text, and plays
           a completion haptic when rest reaches the programmed duration. -->
- [x] Crown-scrub weight/reps; 44pt targets; safe areas (2026-07-08)
      <!-- Digital Crown mode toggles between load and target reps; mode
           controls are 44pt icon buttons and the RACK IT overlay is padded to
           respect compact Watch safe areas. -->
- [x] Verify: visual pass on Watch, dark-first OLED (2026-07-08)
      <!-- User verified the live Watch UI running on-device. Dark-first OLED
           layout, compact states, Crown controls, and RACK IT overlay are
           accepted for this phase. -->

## Phase 6 — Sync (Watch ↔ iPhone)
- [x] `SessionEnvelope` Codable DTOs (2026-07-08)
      <!-- TDD, hardware-free. Expanded Sync/SessionEnvelope.swift: RepMetric/
           SpotEvent/Calibration/LiveTick envelopes + richer CompletedSetEnvelope
           (per-rep metrics, spot events, avg/peak velocity, Epley e1RM). Reuses
           SpotEventKind/SpotReason + Epley (no dup). 8 round-trip tests.
           NOTE: WatchLink encoder must set JSONEncoder.dateEncodingStrategy =
           .iso8601 — Foundation's default is a raw reference-date double. -->
- [x] `WatchLink` WCSession wrapper: live set streaming + finished-session handoff (2026-07-08)
      <!-- Existing iPhone->Watch planned-session link now has the reverse path:
           Watch sends LiveTickEnvelope while reachable and queues finished
           SessionEnvelope handoffs via WCSession userInfo when needed. iPhone
           WatchLink decodes the handoff and imports it through SessionImporter.
           Real paired-device delivery still needs validation. -->
- [x] Persist finished session to SwiftData (envelope→model importer) (2026-07-08)
      <!-- TDD, hardware-free. Persistence/SessionImporter.swift: upsert-by-id
           (no dupes on re-delivery), rep order via repIndex, SpotEvent→
           SpotterEvent (.resolved dropped — no matching stage), find-or-create
           Exercise per LiftKind. In-memory ModelContext tests. 6 tests. -->
- [ ] Write finished workout to HealthKit (on-device)
- [ ] Verify: standalone Watch session appears in iPhone history + Apple Health
      <!-- Watch->iPhone handoff code is wired; needs paired-device validation
           that a real Watch set lands in iPhone history. HealthKit write remains
           separate/open. -->

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
- [x] History list → session → set detail (per-rep metrics, spotter events, e1RM) (2026-07-08)
      <!-- Added iPhone Review tab with a History section. Logged
           WorkoutSessions drill into ordered CompletedSets, per-rep metrics,
           spotter events, set velocity summaries, tonnage, and derived e1RM. -->
- [x] Analytics compute layer (pure): e1RM trend, tonnage series, VBT velocity-at-load, spotter-event freq (2026-07-08)
      <!-- TDD, hardware-free. Sources/.../Analytics/ (SetRecord value type +
           PerformanceAnalytics pure funcs). Reuses Epley (no dup). 11 tests.
           Charts UI below consumes these. -->
- [x] Swift Charts: e1RM trend, volume/tonnage, VBT velocity-at-load, spotter-event freq (wire to Analytics layer) (2026-07-08)
      <!-- Review > Analytics maps SwiftData sessions to SetRecord inputs and
           renders e1RM trend, tonnage, velocity-at-load, and spotter-event
           charts from the pure PerformanceAnalytics layer. -->
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
