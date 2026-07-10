# Spottersaurus Context

## Glossary

- **Program** — A training plan made of ordered Program Days and governed by a progression rule.
- **Program Day** — One scheduled training day inside a Program. It owns ordered Planned Sets.
- **Planned Set** — A prescription for one set: Exercise, target reps, load, AMRAP flag, rest duration, and order within a Program Day.
- **Training Max** — The per-lift load used to resolve percentage-based Planned Sets.
- **Planned Session** — A Program Day selected for execution on the Watch.
- **Live Set** — The currently executing Planned Set on the Watch, including rep count, alert stage, and rest progress.
- **Live Session** — The in-progress execution of a Planned Session on the Watch, from the first Live Set armed to session end (spanning multiple Live Sets and their rests). The unit tracked by the iPhone In-Workout View and Live Activity; ends on session-complete, user-stop, or staleness timeout.
- **In-Workout View** — The iPhone full-screen takeover shown while a Live Session is active (app-wide, dismissible), showing set N-of-M, reps, Mean Concentric Velocity, HR, Alert Stage, and rest.
- **Session Override** — An ephemeral, per-send adjustment to a Planned Session (per-set lift/reps/load/rest/AMRAP) made on the iPhone before Send-to-Watch. Does not mutate the saved Program.
- **Alert Stage** — The spotter warning level for a Live Set: none, grinding, or rack-it.
- **RACK IT** — The Stage-2 alert: abort the rep and return the bar to the rack / dump it on the safeties now, because a sustained stall/grind/pin means the rep is failing. The app's core bail signal for a solo lifter. Preceded by the softer **grinding** (Stage 1) nudge.
- **Setup Phase** — The interval between Start (arm) and the first work rep, during which the lifter unracks/walks out/lifts off and braces. Its motion is not counted as reps. Modelled as the `settling` lifecycle state. _Avoid_: warmup, walkout (the walkout is one activity within it).
- **Grind Tap** — A (now removed from live detection) manual tap signalling a grind. Not usable mid-rep because the hands are locked on the bar — the live interaction model is Start/End only. _Avoid_: manual override.
- **Mean Concentric Velocity** — The VBT headline metric: average bar velocity over a rep's concentric phase, in m/s. A per-rep scalar, resolved and displayed at rep completion (not an intra-rep instantaneous readout).
- **Live Set Lifecycle Event** — An explicit Watch→iPhone signal marking the boundaries of a Live Set: `armed` (set started; carries lift, target reps, weight) and `ended` (racked/completed). Distinct from the per-tick metric stream; drives the iPhone in-workout view, Live Activity, and Watch Always-On Display deterministically.
- **Session Transport** — The abstraction that carries envelopes between Watch and iPhone. Its **Port** (protocol + all send/queue/reconcile logic) lives in SpottersaurusKit and is platform-neutral; its **Adapter** (the concrete `WCSession` wiring) lives in each app target. _Avoid_: WatchLink, connectivity layer (those are adapter implementations, not the concept).
- **Session Snapshot** — A full, idempotent picture of the current Live Session (current set index, lifecycle state, rep count, Alert Stage) that the Watch pushes to the iPhone whenever the link returns, so the mirror self-heals after a dropout. _Avoid_: sync, refresh.
- **Mirror** — The iPhone's read-only projection of Live Session state folded from streamed events and Session Snapshots. The iPhone is never an authority; the Watch owns the state. _Avoid_: copy, replica.
- **Sequence Number** — The monotonic counter stamped on every live tick and Live Set Lifecycle Event, used to fold events idempotently and detect gaps. _Avoid_: version, timestamp (a Sequence Number is neither).
- **Heartbeat** — The ~2 s tick the Watch emits between reps; its recency (not raw `isReachable`) defines whether the Live Session is considered live. _Avoid_: ping, keepalive (the keepalive is the workout session, not this).
- **Calibration Profile** — The persisted per-lift baseline (concentric-tempo baseline + velocity band) captured from warmup reps, loaded when a set is armed to sharpen detection. Distinct from the ephemeral in-set capture state. _Avoid_: baseline, tuning.
- **Spotter Pairing** — A linked person (via CloudKit share) who may see a lifter's Stage-2 alerts, scoped to chosen lifts. In v1 the alert surfaces in-app on sync — there is no real-time push. _Avoid_: friend, buddy, share.
