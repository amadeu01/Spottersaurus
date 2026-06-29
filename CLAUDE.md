# Spottersaurus

Powerlifting **auto-spotter** for Apple Watch + iPhone. The Watch watches the bar via
wrist motion + heart rate during a working set; on a detected stall/grind/pin it fires an
escalating self-alert ("grinding" nudge → loud "RACK IT") so a solo lifter knows to bail.
iPhone plans programs and reviews history; the Watch is the in-gym executor.

> Full product spec & decisions: **`docs/PLAN.md`**. Read it before non-trivial work.

## Platforms
- **iOS 26 / watchOS 26** min (project deploys to 26.5). Latest APIs are fair game.

## Targets
- `Spottersaurus` — iOS app: program builder, history, charts, settings, spotter pairing.
- `Spottersaurus Watch App` — watchOS app: live session execution, sensors, auto-spotter
  alerts. Standalone-capable.
- `SpottersaurusKit` — shared local Swift package: `Model/`, `Detection/`, `Sync/`,
  `Design/`. Schema, detection math, and design tokens live here once.

## Key frameworks
SwiftUI · SwiftData (+ CloudKit private mirror) · WorkoutKit · HealthKit
(`HKWorkoutSession`, `HKLiveWorkoutBuilder`) · CoreMotion (`CMBatchedSensorManager`) ·
WatchConnectivity · Swift Charts.

## Conventions
- Swift Concurrency (async/await, actors for the sensor pipeline; `@MainActor` UI).
- Detection engine is pure and unit-tested against recorded/synthetic IMU buffers — no
  hardware needed to test it.
- Conservative alert posture: never cry wolf; two-stage escalation.
- Design: native port of the design brief — SF Pro Rounded, Liquid Glass /
  `.ultraThinMaterial`, `.continuous` squircles, `Circle().trim` ring gauges,
  `.sensoryFeedback`, dark-first OLED, `.monospacedDigit()` live metrics. 44pt targets.
- Use the `ios-engineer` subagent for Swift work (`.claude/agents/ios-engineer.md`).

## Build
Use project CLI build scripts when present; otherwise `xcodebuild` for the target
scheme/destination. Keep the build green; add tests with detection/model changes.
