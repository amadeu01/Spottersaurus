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
- **Mean Concentric Velocity** — The VBT headline metric: average bar velocity over a rep's concentric phase, in m/s. A per-rep scalar, resolved and displayed at rep completion (not an intra-rep instantaneous readout).
- **Live Set Lifecycle Event** — An explicit Watch→iPhone signal marking the boundaries of a Live Set: `armed` (set started; carries lift, target reps, weight) and `ended` (racked/completed). Distinct from the per-tick metric stream; drives the iPhone in-workout view, Live Activity, and Watch Always-On Display deterministically.
