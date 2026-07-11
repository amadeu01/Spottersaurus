# Squat velocity via fused-gravity projection — compute now, trigger after validation

Date: 2026-07-10
Status: Accepted (refines ADR 0005)

## Context

ADR 0005 (and `LiftKind.usesVelocityPath == false` for squat) assumed wrist
velocity is unusable for a back squat because "the wrist is static." That was
wrong. In a back squat the hands grip the bar and stay locked the whole set: the
wrist is fixed *relative to the bar*, but the bar + shoulders + wrist **translate
vertically together**, so wrist vertical displacement = bar vertical displacement
and **wrist vertical velocity ≈ bar vertical velocity**. The wrist rides the bar;
it is not static in the ground frame.

The historical objections to squat wrist-VBT were orientation and lean, not
absence of motion:
- the wrist sits at an awkward, *changing* tilt and the torso leans through the
  rep — but fused device motion (ADR 0007) supplies the `gravity` vector every
  sample, so we project onto **true vertical** regardless of wrist tilt;
- torso lean adds horizontal wrist motion — discarded by taking only the vertical
  (gravity-projected) component;
- bar wobble / grip micro-motion add noise — `rotationRate`/`attitude` can flag it.

So squat velocity is physically real and computable. What is *not* yet
established is whether on-wrist vertical velocity tracks true bar velocity well
enough to drive the **safety-critical RACK IT trigger**.

## Decision

- **Compute squat velocity now** via fused-gravity vertical projection: run the
  velocity integrator for squat, surface Mean Concentric Velocity, and include it
  in raw captures (ADR 0008).
- **Do not yet trigger** squat alerts on velocity. The squat RACK IT trigger
  stays **tempo + HR** (ADR 0005) until raw captures prove wrist-VBT tracks bar
  velocity. Then promote velocity to the squat trigger (or a hybrid).
- Split the lift capability into two notions: **computes velocity** (all
  wrist-coupled lifts incl. squat) vs **velocity drives alerts** (bench/deadlift
  now; squat after validation). `LiftKind.usesVelocityPath` is replaced/augmented
  accordingly.

## Consequences

- `features.md` and `vbt.md` are updated: squat is no longer "velocity reported
  as 0"; it computes velocity but does not yet alarm on it.
- Validation is a concrete future task (replay squat captures, compare) that gates
  promoting velocity to the squat trigger.
