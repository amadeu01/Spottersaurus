# Spottersaurus — Powerlifting Auto-Spotter for Apple Watch + iPhone

## Context

`Spottersaurus` started as a stock Xcode SwiftData template (single iOS target, deployment **iOS 26.5**, placeholder `Item.swift` + default `ContentView`). No Watch target yet. We are building it into a real native app whose differentiator is an **auto-spotter**: the Apple Watch watches the bar (via wrist motion + heart rate) during a working set and, when it detects a stall/grind/pin, fires an escalating self-alert ("grinding" nudge → loud "RACK IT") so a solo lifter knows to bail the rep. iPhone is the planner/reviewer; the Watch is the in-gym executor.

The styling brief was written in Tailwind/web terms; it is **ported to native SwiftUI** (SF Pro Rounded, Liquid Glass / `.ultraThinMaterial`, `RoundedRectangle` squircles, SF Symbols, `Canvas`/`Path.trim` ring gauges, `.sensoryFeedback` haptics). No web runtime — Watch has none.

Min OS: **iOS 26 / watchOS 26**. APIs available: SwiftData, WorkoutKit, HealthKit, CoreMotion `CMBatchedSensorManager` (high-rate wrist motion on Watch), `.sensoryFeedback`, Liquid Glass.

## Locked decisions (from grilling)

| Branch | Decision |
|---|---|
| Core concept | Watch **auto-spotter** — detect bar stall, alert lifter |
| Lift scope | All three SBD (squat, bench, deadlift) |
| Squat detection | Tempo + HR + manual grind tap (wrist static on back-loaded bar) |
| Bench/dead detection | Wrist-motion stall/velocity (wrists track bar) |
| Spot action | **Self-alert** (haptic + audio) in v1; opt-in human spotter push |
| Device roles | Watch = live executor (standalone-capable); iPhone = plan + review |
| Set model | Planned set + auto-assist (tap-arm → auto rep-count → auto-rack) |
| Data stack | SwiftData local + CloudKit mirror + WatchConnectivity live link + HealthKit write |
| Deliverable | Native SwiftUI both platforms; web design ported to native |
| Programs | iPhone custom builder + 2 presets (5/3/1, linear progression) |
| Detection algo | On-device heuristic + per-user calibration (no ML in v1) |
| Alert posture | Conservative, two-stage escalating |
| v1 scope | **Full vision** — incl. CloudKit sync, human-spotter pairing, charts/e1RM, VBT readout |

## Architecture

### Targets (Xcode)
1. **Spottersaurus** (iOS app) — existing target, gutted of template code.
2. **Spottersaurus Watch App** (watchOS) — new target. Standalone watchOS app, paired to iOS app.
3. **SpottersaurusKit** (shared local Swift package) — model layer, detection engine, sync envelopes, design tokens. Linked by both app targets so the SwiftData schema, detection math, and design system are written once.

Watch Connectivity / CloudKit entitlements on both app targets; HealthKit + Motion usage strings in both Info.plists.

### Shared package `SpottersaurusKit`
- `Model/` — SwiftData `@Model` types. One schema, shared.
- `Detection/` — `SpotEngine`, `RepSegmenter`, `Calibration`, velocity integrator. Platform-neutral (sample buffers in, events out). Unit-testable without a Watch.
- `Sync/` — `SessionEnvelope` Codable DTOs + `WatchLink` (WCSession wrapper) for live set streaming and finished-session handoff.
- `Design/` — `Theme` (colors, type ramp, spacing), reusable views (`RingGauge`, `GlassCard`, `MetricReadout`, `PrimaryButton`). iOS + watchOS conditional sizing.

### Data model (SwiftData, CloudKit-mirrored)
Replace `Item.swift` entirely. Entities:
- `Exercise` — name, `LiftKind` enum (squat/bench/deadlift/accessory), bar-tracking profile (wristTracked vs backLoaded → selects detection path).
- `Program` — name, ordered `[ProgramDay]`, progression rule (`fivethreeone` / `linear` / `custom`).
- `ProgramDay` — ordered `[PlannedSet]`.
- `PlannedSet` — exercise, targetReps, weight or `%1RM`, isAMRAP, restSeconds.
- `WorkoutSession` — date, program ref, `[CompletedSet]`, source device, HealthKit UUID.
- `CompletedSet` — exercise, weight, reps performed, `[RepMetric]`, spotter events, e1RM (Epley), avg/peak concentric velocity.
- `RepMetric` — concentric duration, peak/mean velocity, ROM proxy, flaggedStall bool.
- `UserMaxes` — per-lift training max / 1RM for %-based programming.
- `CalibrationProfile` — per-lift baseline rep tempo + velocity bands captured during warmups.
- `SpotterPairing` — linked spotter (CloudKit share / account), enabled lifts.

CloudKit: private database via SwiftData `ModelConfiguration(cloudKitDatabase: .private)`. History/programs/maxes sync across devices and back up. Live in-set data does **not** go through CloudKit (too slow) — Watch→iPhone via WatchConnectivity.

## Watch app (the executor)

### Session lifecycle
- Start session from a loaded `Program` (synced from phone) or quick free-form.
- Wrap each working block in an **`HKWorkoutSession`** (functional strength training) → keeps app foregrounded, sensors live, HR streaming, writes the workout to Health on end.
- Per-set flow: **Arm** (tap or auto on unrack) → sensors at high rate → live readouts → auto rep count → auto-rack detection (motion settle) → rest timer → next planned set.

### Sensor pipeline
- `CMBatchedSensorManager` high-rate accelerometer + device motion (50–100 Hz) while a set is armed; `HKLiveWorkoutBuilder` for HR.
- `RepSegmenter` splits the stream into eccentric/concentric phases per rep (peak-to-peak on the bar-axis acceleration, gravity-removed).
- **Wrist-tracked lifts (bench, deadlift)**: integrate concentric acceleration → velocity estimate (VBT). Flag stall when mid-concentric velocity collapses toward ~0 before lockout, or concentric duration exceeds the calibrated baseline band.
- **Back-loaded squat**: wrist static, so rely on rep **tempo** (cadence drift), **HR spike**, and a manual **grind tap** (Crown / large screen tap / force press). Velocity path disabled; conservative.

### Detection engine (`SpotEngine`) — conservative two-stage
1. **Calibration**: first warmup sets per lift capture baseline concentric duration + velocity band → `CalibrationProfile`.
2. **Stage 1 — soft nudge**: working rep concentric exceeds baseline by T1 (e.g. +40%) OR velocity dips below the lift's stall band → single light `.sensoryFeedback` tap + on-screen "GRINDING" amber state. Non-alarming.
3. **Stage 2 — RACK IT**: grind persists past T2 (sustained near-zero velocity / no lockout within max-concentric window) → strong continuous haptic + loud audio cue + full-screen red "RACK IT" pulse. If a spotter is paired & enabled, push them an APNs alert simultaneously.
4. Quick lifter dismiss (tap) marks event resolved and stores a false-alarm signal on the `CompletedSet` for later tuning.

Thresholds default conservative; per-lift aware. No ML in v1; engine is pure heuristic and unit-tested against recorded sample buffers.

### Watch UI (native-ported design)
- **Live set screen**: big monospaced-digit (SF Pro **Rounded**) rep counter + concentric velocity, a concentric **ring gauge** that closes per rep, HR, weight. Dark-first OLED black canvas. Glass card layering via `.ultraThinMaterial`.
- **State tinting**: neutral → amber pulse (grinding) → red pulse (rack it). Soft pulsing border on state change.
- **Rest timer** ring between sets; haptic on rest complete.
- Crown-scrub to adjust weight/reps; `.sensoryFeedback` on every increment; 44pt min targets.

## iPhone app (the planner / reviewer)

- **Today / Start**: today's planned session; "Send to Watch" (or auto-sync); standalone-start fallback.
- **Program builder**: `Program` → days → `PlannedSet`s (exercise picker, sets×reps, weight or %1RM, AMRAP, rest). Two seed presets: **5/3/1** and **linear progression**. Progression auto-bumps weights from `UserMaxes` after a logged session.
- **History**: session list → set detail with per-rep metrics, spotter events, e1RM.
- **Charts/analytics**: e1RM trend per lift, volume/tonnage, velocity-at-load (VBT) scatter, spotter-event frequency. Swift Charts.
- **Maxes & calibration**: edit training maxes; view/reset calibration profiles.
- **Spotter pairing**: invite a spotter (CloudKit share / contact), choose which lifts push them alerts.
- **Settings**: detection sensitivity (default conservative; sensitive/safety-max override), units, audio cue choice, Health permissions.
- Native design system: Liquid Glass cards, dark/light "Pro Cosmic Dark" / "Pro Pure Light" palettes, SF Pro Rounded display weights, monospaced metric readouts, press-scale + smooth value transitions.

## Design system port (web brief → native)

| Web brief | Native SwiftUI |
|---|---|
| `bg-slate-950` / OLED black | `Color.black` canvas, dark-first |
| `bg-slate-900/60 backdrop-blur` glass card | `RoundedRectangle(cornerRadius: 24, style: .continuous)` + `.ultraThinMaterial` / Liquid Glass |
| `rounded-3xl` / `rounded-[40px]` | `.continuous` squircles, 24 / 40 radii |
| emerald / amber / rose accents | tokens: optimal `#33A853`, caution `#FF9800`, alert coral red |
| `font-black tracking-tight` display | SF Pro **Rounded**, `.bold`/`.heavy`, tight tracking |
| `font-mono` metric readouts | `.monospacedDigit()` / SF Mono for live numbers |
| `active:scale-95`, `transition-all` | `.scaleEffect` on press, `.animation(.easeOut, ...)`, `.sensoryFeedback` |
| progress rings (`strokeDasharray`) | `Circle().trim(from:to:)` ring gauges / `Canvas` |
| safe areas (notch / home bar) | `.safeAreaInset`, respect Watch bezel + Dynamic Island |

Centralized in `SpottersaurusKit/Design/Theme.swift` so both targets share tokens.

## Build order (full-vision v1, sequenced to de-risk)

1. **Project setup** — add Watch App target + `SpottersaurusKit` local package; entitlements (HealthKit, Motion, CloudKit, App Groups for WC); Info.plist usage strings; delete `Item.swift`/template `ContentView`.
2. **Data model** — SwiftData schema in the package; CloudKit private config; seed presets; `UserMaxes`/`CalibrationProfile`.
3. **Detection engine** — `RepSegmenter` + `SpotEngine` + velocity integrator, **unit-tested against recorded/synthetic sample buffers** (the core risk — prove it on data before wiring hardware).
4. **Watch session** — `HKWorkoutSession` + `CMBatchedSensorManager` + `HKLiveWorkoutBuilder`; feed live samples into the engine; calibration flow.
5. **Watch UI** — live set screen, ring gauges, state tinting, escalating alert (haptic + audio), rest timer.
6. **Sync** — `WatchLink` (WCSession) live + finished-session handoff to iPhone; persist + HealthKit write.
7. **iPhone planner** — builder, presets, maxes, Today/Start, send-to-Watch.
8. **iPhone review** — history, set detail, Swift Charts analytics.
9. **Human spotter** — pairing UI + CloudKit share/APNs push on Stage-2 alert.
10. **Design polish pass** — apply the ported design system end-to-end; motion/haptics; light/dark.

## Critical files
- Replace: `Spottersaurus/Item.swift`, `Spottersaurus/ContentView.swift`, `Spottersaurus/SpottersaurusApp.swift` (point at shared schema).
- New: Watch App target + `Packages/SpottersaurusKit/` local package.
- New (package): `Model/*.swift`, `Detection/{RepSegmenter,SpotEngine,VelocityIntegrator,Calibration}.swift`, `Sync/{WatchLink,SessionEnvelope}.swift`, `Design/{Theme,RingGauge,GlassCard,MetricReadout}.swift`.
- New (Watch): session engine + live UI views.
- New (iOS): builder, history, charts, pairing, settings views.

## Verification
- **Engine**: `SpottersaurusKit` unit tests — feed recorded/synthetic accelerometer buffers for clean reps, a grind, and a hard pin; assert Stage-1 and Stage-2 fire at the right samples and do **not** fire on clean reps (false-alarm guard). Squat path asserted on tempo/HR + manual tap only.
- **Watch on-device**: run a real bench/deadlift session on Apple Watch (Simulator can't produce real IMU) — confirm rep auto-count, auto-rack, calibration, and that a deliberately slow grind triggers escalation while normal reps stay silent. Squat: confirm manual grind tap + HR path.
- **Sync**: complete a Watch session standalone → confirm it appears in iPhone history and Apple Health; edit a program on iPhone → confirm it loads on Watch.
- **CloudKit**: sign into a second device → confirm programs/history/maxes sync.
- **Spotter**: trigger a Stage-2 alert with a paired spotter → confirm push arrives.
- **Design**: visual pass in light + dark on both devices against the ported design tokens; verify 44pt targets, safe-area insets, haptics on press/state-change.
