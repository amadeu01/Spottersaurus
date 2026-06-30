<p align="center">
  <img src="docs/banner.png" alt="Spottersaurus — powerlifting auto-spotter for Apple Watch + iPhone" width="100%">
</p>

# Spottersaurus

> Powerlifting **auto-spotter** for Apple Watch + iPhone.

The Apple Watch watches the bar via wrist motion + heart rate during a working set.
On a detected stall, grind, or pin it fires an **escalating self-alert** — a soft
"grinding" nudge, then a loud **RACK IT** — so a solo lifter knows to bail the rep.
The iPhone plans programs and reviews history; the Watch is the in-gym executor.

## Features

- 🦖 **Auto-spotter** — conservative, two-stage stall detection (grind → RACK IT)
- 🏋️ **All three SBD** — bench/deadlift via wrist velocity; squat via tempo + HR + manual grind tap
- ⌚ **Watch-first** — runs a standalone `HKWorkoutSession` with high-rate CoreMotion + HR
- 📊 **Bar-speed (VBT)** — concentric velocity readouts and velocity-at-load charts
- 📱 **iPhone planner** — custom program builder + 5/3/1 and linear-progression presets
- ☁️ **Synced** — SwiftData + CloudKit private mirror; writes finished workouts to Apple Health

## Platforms

iOS 26 / watchOS 26. SwiftUI · SwiftData · WorkoutKit · HealthKit · CoreMotion ·
WatchConnectivity · Swift Charts.

## Project layout

| Target | Role |
|---|---|
| `Spottersaurus` | iOS app — planner / reviewer |
| `Spottersaurus Watch App` | watchOS app — live executor + auto-spotter |
| `SpottersaurusKit` | shared package — Model · Detection · Sync · Design |

## Status

🚧 Early development. Phase 1 (project + shared package + Watch target scaffold) is in.
See the full spec in [`docs/PLAN.md`](docs/PLAN.md) and the build checklist in
[`docs/TASKS.md`](docs/TASKS.md).

## Build

```bash
# shared package
cd Packages/SpottersaurusKit && swift test

# iOS app
xcodebuild build -scheme Spottersaurus -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

<sub>Mascot art and brand: navy + safety-orange, the Spottersaurus powerlifting T-rex.</sub>
