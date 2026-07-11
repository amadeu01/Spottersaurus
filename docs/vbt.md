# VBT — how bar velocity is computed from the sensors

**VBT (Velocity-Based Training)** measures how fast the bar moves in the
lifting (concentric) phase of a rep. Velocity falls as a lifter fatigues, so a
collapsing concentric velocity is the auto-spotter's earliest objective sign a
rep is failing. This doc shows exactly how we get from raw sensor samples to
velocity, distance, and time. The code lives in
`Packages/SpottersaurusKit/Sources/SpottersaurusKit/Detection/`
(`GravityRemover`, `RepSegmenter`, `VelocityIntegrator`).

## The physics in one line

Acceleration integrates to velocity; velocity integrates to distance.

```
a(t)  →  v(t) = v(0) + ∫ a dt  →  x(t) = x(0) + ∫ v dt
```

Everything below is that, done numerically on timestamped samples, with one
correction for sensor drift.

## Step 1 — raw sample → bar-axis acceleration

The Watch streams fused **device motion** (`CMBatchedSensorManager.deviceMotionUpdates()`,
200 Hz): `userAcceleration` (linear accel, gravity already removed) and the
`gravity` unit vector. We project `userAcceleration` onto the bar (vertical) axis
= the gravity direction, then convert g → m/s²:

```
axialMS2 = (userAcceleration · (−gravitŷ)) × 9.80665
```

(`−gravity` because CoreMotion's gravity points toward the ground; up is
positive.) See `GravityRemover.axialAcceleration(deviceMotion:)`. For the raw
accelerometer fallback, gravity is EMA-estimated instead — same output type
(`LinearSample.axialMS2`).

## Step 2 — integrate to velocity (worked example)

Take one clean bench concentric, ~0.8 s. For clarity we sample at 10 Hz
(`dt = 0.1 s`); the real pipeline is 200 Hz. Bar-axis acceleration (m/s²) —
positive while pushing up, negative while decelerating into lockout:

| t (s) | a (m/s²) | v = v₋₁ + ½(a+a₋₁)·dt | x = x₋₁ + ½(v+v₋₁)·dt |
|------:|---------:|----------------------:|----------------------:|
| 0.0 | 0.000 | 0.000 | 0.000 |
| 0.1 | 1.414 | 0.071 | 0.004 |
| 0.2 | 2.000 | 0.241 | 0.019 |
| 0.3 | 1.414 | 0.412 | 0.052 |
| 0.4 | 0.000 | 0.483 | 0.097 |
| 0.5 | −1.414 | 0.412 | 0.142 |
| 0.6 | −2.000 | 0.241 | 0.175 |
| 0.7 | −1.414 | 0.071 | 0.190 |
| 0.8 | 0.000 | 0.000 | 0.188 |

**v** column = trapezoidal integration of **a**. **x** column = trapezoidal
integration of **v**. Read off the VBT metrics:

- **Duration (time)** = 0.8 s (concentric end − start).
- **Peak velocity** = max(v) ≈ **0.48 m/s** (mid-rep, where accel crosses zero).
- **Displacement (ROM proxy)** = final x ≈ **0.19 m**.
- **Mean Concentric Velocity** = displacement / duration ≈ 0.19 / 0.8 ≈
  **0.24 m/s** (equivalently, the mean of the v column).

At 200 Hz these converge to the smooth closed-form values (peak ≈ 0.51, mean ≈
0.25 m/s); the coarse 10 Hz table just makes the arithmetic visible.

## Step 3 — drift correction (why velocity doesn't run away)

In the ideal table, v started and ended at exactly 0. Real accelerometers carry a
small **bias**, so a raw integral drifts — v never quite returns to 0 and the
error compounds. We exploit a physical fact: a powerlifting concentric **starts
and ends at rest** (bottom sticking point → lockout). So we **detrend**: subtract
the straight line that forces both endpoints of the concentric to zero (a
Zero-velocity UPdaTe / ZUPT). That is a high-pass filter removing exactly the
linear drift a constant bias produces. See `VelocityIntegrator.integrate(_:)`
(`raw[i] − endVel · (t−t0)/span`). `RepSegmenter` applies the same idea between
reps, clamping v to 0 during the still moments so drift can't cross rep
boundaries.

## Which lifts use velocity

**Bench** and **deadlift** use velocity as the alert trigger — the wrist tracks
the bar, so wrist velocity ≈ bar velocity.

**Squat** also *computes* velocity: the hands hold the bar on the back for the
whole set, so the wrist rides the bar's vertical travel (wrist vertical velocity
≈ bar vertical velocity), and fused device-motion gravity (ADR 0007) lets us
project onto true vertical despite the tilted, leaning wrist. But squat's
**alert trigger stays tempo + HR** until raw captures validate that wrist-VBT
tracks bar velocity closely enough to bail on — velocity is displayed and
captured, not yet alarmed on. See
[`adr/0009-squat-velocity-via-fused-gravity.md`](adr/0009-squat-velocity-via-fused-gravity.md)
and [`adr/0005-no-mid-rep-manual-input.md`](adr/0005-no-mid-rep-manual-input.md).

## Live ticks vs raw data — what "coalesce-to-latest" drops (and doesn't)

The Watch computes all of the above **locally, on the full sample stream** — no
sample is skipped in detection. Separately, the Watch sends the iPhone a
low-frequency **live tick** (running metrics for the glanceable mirror). `WCSession`
rate-limits messages, so if a send is still in flight when newer ticks arrive, we
keep only the **latest** tick to send next and discard the stale intermediate
ones — "coalesce-to-latest" (`LiveTickCoalescer`,
[`adr/0001`](adr/0001-live-session-surfaces-and-transport.md)).

What that drops: redundant **mirror display updates** — never the underlying
**raw sensor data**, which the Watch keeps and processes in full. If we also want
the raw stream on the iPhone for offline processing, that is a separate durable
bulk transfer, not the live tick — see
[`adr/0008-raw-sensor-capture.md`](adr/0008-raw-sensor-capture.md).
