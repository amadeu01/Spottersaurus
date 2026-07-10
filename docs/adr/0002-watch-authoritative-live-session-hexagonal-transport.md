# Watch-authoritative live session over a hexagonal, Kit-owned transport

Date: 2026-07-10
Status: Accepted

## Context

The live session previously kept **two independent writers** of set/cursor and
liveness state — `LiveSessionMonitor` + `PhoneWatchSessionMonitor` on the iPhone
and `WatchPlannedSessionStore`'s cursor on the Watch — with no authority between
them. Sending a new/edited session left the two devices disagreeing about which
set was current (the "out of sync" bug). The `WCSession` send/queue/fallback
logic and its wire keys were also duplicated verbatim across `WatchLink`
(iPhone) and `WatchPlannedSessionStore` (Watch), kept in sync only by a comment,
and untestable on macOS.

## Decision

- **The Watch is the sole owner of Live Session state** (set cursor, lifecycle,
  rep count, Alert Stage). It has the sensors and must run standalone. The
  iPhone holds only a **mirror** that folds streamed events — it never advances
  its own cursor. One writer ⇒ no reconciliation conflicts.
- **Transport is hexagonal.** Kit defines a `SessionTransport` **port**
  (protocol) plus all domain logic — the Live Session reducer, `PlannedSessionCursor`,
  `WireKeys`, the offline queue/reconcile policy, and the Codable envelopes —
  all pure and macOS-`swift test`-able. Each app target ships a thin
  `WCSessionTransport` **adapter** conforming to the port. `WatchLink` and
  `WatchPlannedSessionStore` shrink to adapters + platform wiring.
- **Kit must not import WatchConnectivity** (it isn't on macOS and would make the
  transport logic compile out of tests). The port keeps the OS dependency in the
  app targets.

## Considered Options

- *Full transport in Kit behind `#if canImport(WatchConnectivity)`* — shares more
  literal code but recreates the exact untestable-on-macOS gap we are fixing.
- *Replicated + reconciled state (both devices write)* — only needed if the
  iPhone must drive the set mid-session, which it must not (standalone-Watch is a
  locked product decision). Rejected as needless conflict surface.

## Consequences

- Fixes the audit's Information-Leakage finding (wire keys) and the dual-source-
  of-truth Knowledge-Duplication finding in one move.
- The iPhone mirror is only ever as fresh as the last streamed event/snapshot —
  see ADR 0004 for how gaps are recovered.
