# No mid-rep manual input; squat detection without a grind tap

Date: 2026-07-10
Status: Accepted

## Context

The detection engine (`SpotEngine`) accepts `manualTaps` and treats a tap inside
a rep as a first-class grind/pin signal — it can raise Stage 1 alone and satisfy
squat Stage 2. But for every SBD lift the lifter's **hands are locked on the bar
for the entire working set** (squat: gripping the bar on the back; bench/dead:
gripping the bar). There is no hands-free moment, and no reachable gesture
(screen tap, Digital Crown, double-tap pinch, all need a free hand/fingers)
during a rep. The only hands-free interactions are **Start** (before the set) and
**End** (after). So a mid-rep manual tap is physically impossible and cannot be a
live detection signal.

## Decision

- **The live interaction model is Start / End only.** No mid-rep input exists;
  detection must be fully automatic during the set.
- **Remove `manualTaps` from live detection** in both `SpotEngine` paths. (A
  between-sets, hands-free "that was a false alarm" tuning tap during rest is a
  possible future signal, but it is *not* live detection and is out of scope
  here.)
- **Squat Stage 2 without the tap:** fire on an **extreme tempo blowout alone**
  (`ratio > rackDurationMultiplier`, an unambiguously slow grind) **OR** a
  moderate blowout corroborated by an **HR spike**. Bench/deadlift keep the
  velocity (VBT) path unchanged.

## Consequences

- Squat's automatic RACK IT is inherently more conservative/later than
  bench/dead VBT (HR lags strain; tempo needs the rep to visibly drag). This is
  an accepted limitation of wrist-on-back sensing — see the "honest weakness" in
  `docs/features.md`. A future rotation-rate/attitude signal could sharpen it.
- Any Watch UI affordance implying a live "grind tap" must be removed or
  repurposed to a between-sets action.
