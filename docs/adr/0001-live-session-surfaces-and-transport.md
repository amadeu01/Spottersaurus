# ADR 0001 — Live-session surfaces and Watch→iPhone transport

Date: 2026-07-09
Status: Accepted

## Context

Spottersaurus executes a working set on the Apple Watch (local motion + HR, no
network hop) and mirrors it to the iPhone. We want, during a live set: an
in-workout takeover on the iPhone foreground, an iPhone Live Activity (lock
screen + Dynamic Island), a Watch Always-On Display, and a "real-time" velocity
readout. The Watch↔iPhone link is `WCSession`; there is **no push/APNs server**
in this project (persistence is CloudKit private mirror only).

Two hard realities shape the design:

1. **The Watch is the only true real-time surface.** It reads IMU/HR locally and
   renders with no transport delay. The iPhone only sees metrics through a
   `WCSession` message hop, which the OS rate-limits and which is unsuitable for
   high-frequency (10–20 Hz) streaming.
2. **ActivityKit constraints** (confirmed against Apple docs): starting a Live
   Activity requires the app in the **foreground** (`Activity.request` throws
   `ActivityAuthorizationError.visibility` in the background); `activity.update`
   works foreground or background but only while the app is executing; frequent
   updates while the phone is locked require an **APNs push token + server**.
   `Text(timerInterval:)` auto-advances a timer on the lock screen with no push.

## Decision

- **Watch = the real-time instrument.** iPhone + lock screen are **glanceable**
  low-frequency surfaces, not per-frame velocity mirrors.
- **Velocity metric = Mean Concentric Velocity per rep**, resolved and shown at
  rep completion (VBT headline), not an intra-rep instantaneous trace.
- **Explicit Live Set lifecycle events** (`armed` carrying lift/target/weight,
  `ended` on rack/complete) drive all surfaces deterministically, replacing the
  tick-recency heuristic. Ticks carry running metrics + current Alert Stage.
- **Foreground transport = coalesce-to-latest.** Never drop the freshest tick
  while a send is in flight; send the latest pending tick when the in-flight one
  completes. Rep-completion ticks are prioritized; a ~2 s heartbeat carries
  HR/elapsed between reps. No long hard failure-backoff.
- **Live Activity is started from the foreground** (piggybacked on "Send to
  Watch"). Elapsed/rest use `Text(timerInterval:)` (always live, no push). Reps,
  velocity, HR, Alert Stage update via `activity.update` when the app is
  reachable plus opportunistic `transferUserInfo` background-wakes (few-second
  coalesced staleness while locked). Alert-stage changes are high priority.
- **No APNs server in v1.0.0.** True per-rep updates while the phone is locked,
  and reliable background *start* of the Activity, are deferred to a post-1.0
  APNs `.token` path.

## Consequences

- The phone in-workout view updates within a `WCSession` round-trip (~sub-second)
  of each rep — the previous ~1 s stall (drop-on-in-flight) is gone.
- While the phone is **locked**, stats refresh every few seconds, not per rep;
  elapsed/rest still tick live via the system.
- A set armed purely from the Watch while the phone was **already locked** gets
  no lock-screen Live Activity until the phone is next unlocked/foregrounded
  (no background start without a server). Accepted limitation.
- The safety alarm remains the **Watch** (haptics + RACK IT); the Live Activity
  is informational only, so its staleness is never safety-critical.
- Adding APNs later is additive (a push token on start + a small server); it does
  not invalidate any of the above.
