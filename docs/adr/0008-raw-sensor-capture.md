# Raw sensor capture, durable transfer, and offline replay

Date: 2026-07-10
Status: Accepted

## Context

The Watch processes the 200 Hz device-motion stream locally and only sends the
iPhone low-frequency summary ticks (coalesced, ADR 0001). The raw stream is
currently discarded after processing. We want to **keep every raw sample** —
from Start (arm) through End, including the setup/walkout — so we can reprocess a
session offline for detection tuning and debugging, and inspect data per set /
exercise / workout. The detection engine is already pure and built to run against
recorded buffers, so replaying captures through it is the natural debug loop.

Data volume: device motion at 200 Hz ≈ ~112 bytes/sample ≈ ~1.3 MB per minute of
capture; a workout is tens of MB. That is fine as files, too big for live
`WCSession` messaging, and wrong for CloudKit.

## Decision

- **Capture scope:** buffer all samples (`DeviceMotionSample` + `HRSample` +
  lifecycle markers) per **set**, from arm through rack/end, including the setup
  phase (that data is needed to tune the ADR 0006 rep-1 gate).
- **Transfer:** per-set, via `WCSession.transferFile` **as soon as the set ends**
  (durable, background, survives app suspension). Not the live tick path.
  Smaller files, survives a mid-workout interruption, inspectable per set.
- **Format:** compact **binary** (`Codable`) as the stored primary; an on-demand
  **NDJSON/CSV export** for external inspection / the LLM debug flow (mirrors the
  existing debug-log NDJSON sink).
- **Storage & organization (iPhone):** local files grouped
  **workout → exercise → set**, referenced by set id from the `WorkoutSession` /
  `CompletedSet`. **Not** CloudKit-mirrored (too big). Retention: keep the last N
  sessions with manual delete/offload.
- **Replay:** a pure Kit function feeds a stored capture back through `SpotEngine`
  to reproduce events/metrics deterministically, exposed from the Debug surface.

## Consequences

- Raw storage is local-only and pruned; it is a debug/tuning asset, not synced
  user data. Anything that must sync (derived metrics, spotter events) already
  lives in the SwiftData model.
- The capture format is a new wire/disk contract; version it so old captures
  still decode.
