# Architecture

How Spottersaurus is put together, from the whole system down to the module
graph. Vocabulary is in [`../CONTEXT.md`](../CONTEXT.md); the decisions behind
this shape are in [`adr/`](adr/); the work sequence is in [`PLAN.md`](PLAN.md).

---

## 1. System (high level)

Three targets. The **Watch is the authoritative live executor** (sensors, runs
standalone); the **iPhone plans and mirrors**. Live in-set data crosses via
**WatchConnectivity**; durable data (programs, history, maxes, calibration) syncs
via **CloudKit private mirror**; finished workouts are written to **Apple Health**.

```mermaid
graph TD
    subgraph Phone["iPhone — Spottersaurus"]
        iPlan["Planner + Review"]
        iMirror["Live Session Mirror"]
        iAdapter["WCSessionTransport adapter"]
    end

    subgraph Watch["Apple Watch — Spottersaurus Watch App"]
        wLive["Live Set executor (authoritative)"]
        wSensors["CoreMotion + HealthKit HR"]
        wAdapter["WCSessionTransport adapter"]
    end

    Kit["SpottersaurusKit (shared package)"]
    Cloud[("CloudKit private DB")]
    Health[("Apple Health")]

    iPlan --> Kit
    iMirror --> Kit
    wLive --> Kit
    wSensors --> wLive

    wAdapter <-->|"live ticks · lifecycle · snapshot · finished session"| iAdapter
    iAdapter --> iMirror
    wLive --> wAdapter

    iPlan <-->|"SwiftData mirror"| Cloud
    wLive <-->|"SwiftData mirror"| Cloud
    wLive -->|"HKWorkoutSession end"| Health

    classDef auth fill:#33A853,stroke:#1e7e34,color:#fff
    class wLive auth
```

The Watch↔iPhone link is `WCSession`; there is **no push/APNs server** (see
[ADR 0001](adr/0001-live-session-surfaces-and-transport.md)). The iPhone can wake
the Watch straight into an armed workout via
`HKHealthStore.startWatchApp(with:)` ([ADR 0003](adr/0003-connection-keepalive-and-liveness.md)).

---

## 2. Shared package `SpottersaurusKit` (low level)

Everything written once lives here — schema, detection math, session logic,
transport domain, design tokens — so both apps consume one source of truth. The
package builds and unit-tests on **macOS** (`swift test`), so it holds **no
device-only frameworks** (HealthKit / CoreMotion / WatchConnectivity live in the
app targets, behind ports).

Dependencies are acyclic and point inward at the pure `Detection` core. `Model →
Detection` is the only cross-layer edge, and it points at the most stable module
(healthy per the Stable Dependencies Principle).

```mermaid
graph TD
    subgraph Kit["SpottersaurusKit"]
        Detection["Detection — SpotEngine, RepSegmenter, VelocityIntegrator, Calibration (pure)"]
        Model["Model — SwiftData @Model types + schema"]
        Session["Session — LiveSessionState, SetLifecycleController, cursor (reducers)"]
        Sync["Sync — Codable envelopes, WireKeys, LiveTickCoalescer, SessionTransport port"]
        Analytics["Analytics — e1RM / tonnage / VBT (pure)"]
        Progression["Progression — 5/3/1, linear (pure)"]
        Persistence["Persistence — SessionImporter, HealthSyncPersister"]
        HKPorts["HealthKit — protocols only (ports)"]
        Diagnostics["Diagnostics — AppLogger + sinks"]
        Design["Design — Theme, RingGauge, GlassCard (SwiftUI tokens)"]
    end

    Model --> Detection
    Session --> Detection
    Session --> Sync
    Sync --> Model
    Analytics --> Model
    Persistence --> Model
    Progression --> Model

    classDef core fill:#33A853,stroke:#1e7e34,color:#fff
    class Detection core
```

| Layer | Responsibility |
|---|---|
| `Detection` | Sample buffers in, `SpotEvent`/`RepResult` out. Pure, hardware-free, exhaustively unit-tested. |
| `Model` | The one SwiftData schema both apps share; CloudKit-mirrored. |
| `Session` | Deterministic reducers that sequence a set (arm → reps → rack → rest) and fold the iPhone Mirror. Time injected. |
| `Sync` | Wire format: envelopes + `WireKeys` + coalescer + the `SessionTransport` port. |
| `Analytics` / `Progression` | Pure functional cores over `Model`. |
| `Persistence` | Maps envelopes ↔ SwiftData; writes to Health. |
| `Design` | Shared visual tokens; self-contained. |

---

## 3. Session Transport (hexagonal)

The transport is a **port in Kit, adapter in each app** (see
[ADR 0002](adr/0002-watch-authoritative-live-session-hexagonal-transport.md)).
All send / queue / coalesce / reconcile logic and the wire keys are pure and
macOS-testable; only the `WCSession` wiring is per-target. This removes the
duplicated wire keys and the untestable transport code the
[architecture audit](#audit) flagged.

```mermaid
graph LR
    subgraph KitSide["SpottersaurusKit (pure, tested)"]
        Port["SessionTransport (port protocol)"]
        Logic["send/queue/coalesce/reconcile + WireKeys + envelopes"]
        Port --- Logic
    end

    subgraph PhoneSide["iPhone target"]
        PAdapter["WCSessionTransport adapter"]
    end
    subgraph WatchSide["Watch target"]
        WAdapter["WCSessionTransport adapter"]
    end

    PAdapter -.implements.-> Port
    WAdapter -.implements.-> Port
    PAdapter --> WC1["WatchConnectivity"]
    WAdapter --> WC2["WatchConnectivity"]
```

---

## 4. Live Session data flow

The Watch owns the state; the iPhone folds a **Mirror** from a stream of
sequence-numbered events. A dropout self-heals because the Watch pushes one full
**Session Snapshot** whenever the link returns; the finished session always
travels the durable queue ([ADR 0004](adr/0004-offline-reconcile-and-calibration-persistence.md)).

```mermaid
sequenceDiagram
    participant S as Sensors (CoreMotion/HR)
    participant W as Watch (authoritative)
    participant T as Session Transport
    participant P as iPhone Mirror

    W->>T: Lifecycle `armed` (seq n)
    T->>P: fold → In-Workout View
    loop each rep / ~2s heartbeat
        S->>W: motion + HR samples
        W->>W: SpotEngine → rep metrics + SpotEvents → lifecycle
        W->>T: live tick (reps, MCV, HR, AlertStage, seq)
        T-->>P: coalesce-to-latest → mirror
    end
    Note over T,P: link drops mid-set
    W-->>W: keeps running (HKWorkoutSession)
    Note over T,P: link returns
    W->>T: Session Snapshot (set index, state, reps, AlertStage)
    T->>P: idempotent fold → mirror correct again
    W->>T: Lifecycle `ended` + finished session (durable queue)
    T->>P: persist to history + Health
```

---

## <a id="audit"></a>Architecture audit

The module structure was audited (Brooks-Lint) at **89/100**, no criticals:
clean layering, acyclic dependencies, pure detection core, strong DI seams.
Open follow-ups — shared `WireKeys`, `SessionTransport` extraction, splitting the
Watch `LiveSetViewModel` — are scheduled in Phase 2 of [`PLAN.md`](PLAN.md).
