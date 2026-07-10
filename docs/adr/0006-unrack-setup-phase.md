# Unrack / setup phase before rep detection

Date: 2026-07-10
Status: Accepted

## Context

After the lifter presses Start (arms the set), there is a **setup phase** before
the first work rep: the squatter walks the bar out of the J-hooks, steps back,
sets stance and braces; the bencher lifts off and settles; the deadlifter
approaches and sets grip. This produces real wrist + whole-body motion that is
**not a rep**. Today `arm()` immediately feeds motion to the `RepSegmenter`, so
the walkout/lift-off can be miscounted as a rep and pollute the calibrated tempo
baseline. There is no hands-free moment to press a second "begin" button (by the
time the lifter is braced, the hands are already locked on the bar).

## Decision

- Add an explicit **`.settling` state** to `SetLifecycleController` between
  `armed` and `repping`. Motion during `.settling` is not counted as reps.
- **Auto-detect the transition:** leave `.settling` only after a brief
  still/braced period is observed (walkout/lift-off complete), then gate the
  first rep on the lift-appropriate pattern:
  - squat / bench (wrist-tracked or back-loaded, bar starts at the top): the
    first genuine **eccentric → concentric** excursion.
  - deadlift (bar starts on the floor): the first sustained **concentric-from-
    rest** excursion (no preceding eccentric).
- Fully automatic — no extra press. All logic is pure (`SetLifecycleController`
  + `RepSegmenter`) and unit-testable on macOS.

## Consequences

- Warmup calibration and rep counting both start from the first *real* rep, so
  the tempo baseline is clean and the walkout never triggers a false Stage-1.
- The segmenter needs a per-lift rep-1 gate (deadlift differs from squat/bench),
  which the current sign-based phase reader does not yet encode.
