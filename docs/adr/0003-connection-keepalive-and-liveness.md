# Connection keepalive, heartbeat liveness, and iPhone-launches-Watch

Date: 2026-07-10
Status: Accepted

## Context

The Watch↔iPhone link "cut" mid-session: liveness was derived from raw
`WCSession.isReachable`, which flaps on brief foreground/background transitions
and read every blip as a disconnect; the Watch adapter never re-activated a
deactivated session (the iPhone side did); and a stalled RACK IT screen could
keep the app from progressing. A tempting but wrong fix is to lean on a Live
Activity to "keep the exercise alive."

## Decision

- **`HKWorkoutSession` is the keepalive anchor.** A workout session runs for the
  whole working block, keeping the Watch app foregrounded and sensors live —
  this is what actually prevents the drop.
- **Liveness = heartbeat, not raw reachability.** A session is "live" when a
  sequenced tick/heartbeat (the ~2 s heartbeat from ADR 0001) arrived within a
  bounded window. A reachability blip no longer reads as a drop; the
  "reconnecting/stale" state appears only after the window lapses and clears on
  the snapshot-on-reconnect (ADR 0004). Both adapters auto-reactivate on
  `sessionDidDeactivate` / activation errors.
- **The iPhone launches the Watch into the workout.** "Send to Watch" uses
  `HKHealthStore.startWatchApp(with: HKWorkoutConfiguration)` to launch/wake the
  paired Watch straight into the armed session. This is a legitimate fitness use
  of the API.
- **A Live Activity is a glanceable lock-screen mirror only — never a keepalive.**

## Constraints not visible in the code

- Per Apple's docs, **Live Activities do not keep an app running, do not prevent
  suspension, and do not keep a workout alive.** They update only while the app
  runs foreground or via APNs — and this project has **no push server**
  (ADR 0001). Any locked-screen, high-frequency mirroring is therefore out of
  reach without a server; the Live Activity stays low-frequency and glanceable.
