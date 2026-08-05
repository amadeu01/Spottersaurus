# Spec — Custom Program Import (paste / manual, RPE + mesocycle labeling)

**Status:** ready-for-agent (no ticket tracker configured for this repo — see
`docs/backlog.md` for how this repo tracks execution; break this spec into
`backlog.md` tickets via `/to-tickets` when ready to build).

## Problem Statement

The user's real powerlifting programs come from a coach as freeform
Portuguese-language shorthand text — a weekly block labeled by mesocycle and
week number, broken into numbered days, each day a list of exercises with
ramp/pyramid set schemes (`60/7, 100/4, 155kg/5reps x3sets`), RPE-prescribed
accessory work (`4x12@9(RPE)`), free-text rest intervals (`90s`, `4-5mins`),
`(Filmar)` film-reminder flags, and `OFF/DESCANSO` rest days.

Today the only way to get a program into Spottersaurus is the Program
Builder's one-row-at-a-time manual entry, which has no concept of RPE-based
loads, no way to label which mesocycle/week a program belongs to, and no bulk
entry path — so a real coach-authored program currently has to be
hand-transcribed set by set, which is slow enough that the user's actual
training program doesn't make it into the app, blocking the app's core
purpose (tracking real squat/bench/deadlift progression) for anyone who
doesn't use the built-in 5/3/1 or Linear presets.

## Solution

Add a "paste program" quick-import path alongside the existing manual builder:
the user pastes a block of coach-shorthand text, an on-device pure parser
(`SpottersaurusKit`) converts it into a structured, fully editable draft
(days → exercises → planned sets), and the draft opens in the existing
Program Builder UI for review/correction before saving — the parser never
auto-saves unreviewed output. Manual entry through the existing builder
remains available and unchanged as a fallback / alternative for anyone who'd
rather type directly or fix a bad parse from scratch.

`Program` gains optional mesocycle/week labels so multiple weeks pasted from
the same coach block are distinguishable in the program list, without any
relational schema change. `PlannedSet`'s load gains an RPE-based case so
accessory work can be prescribed the way it's actually written. Because
Analytics/History already key everything off `LiftKind` (squat/bench/deadlift)
via `Exercise.kind`, no analytics changes are needed — any exercise the
parser (or manual entry) recognizes as one of the big three lifts flows
straight into the existing e1RM trend, tonnage, and velocity-at-load charts.

## User Stories

1. As a lifter following a coach-authored program, I want to paste the whole
   week's text block into the app, so that I don't have to retype every set
   by hand.
2. As a lifter pasting a program, I want to see the parsed result as an
   editable draft in the familiar Program Builder before it's saved, so that
   I can catch and fix anything the parser got wrong.
3. As a lifter, I want a set written as `155kg/5reps x3sets` to become three
   identical planned sets at 155kg for 5 reps, so that ramp/pyramid schemes
   come in correctly without manual duplication.
4. As a lifter, I want a warm-up ramp like `20/15, 60/7, 100/4, 125/3, 140/2`
   to become five separate planned sets in ascending order, so that the full
   warm-up progression is preserved, not just the work sets.
5. As a lifter, I want `4x12@9(RPE)` to become four planned sets targeting 12
   reps at RPE 9 (not a fixed kg number), so that RPE-based accessory
   prescriptions are represented the way my coach actually writes them.
6. As a lifter with an RPE-prescribed set, I want to be prompted for the
   actual weight I used when I send that day to the Watch, so that the
   auto-spotter and history still get a concrete number even though the
   program itself didn't specify one.
7. As a lifter, I want `Intervalo: 90s`, `Intervalo: 4-5mins`, and
   `Intervalo: 2mins` to all be recognized as rest periods and applied to the
   right set/exercise, so that I don't have to manually re-enter rest times.
8. As a lifter, I want `(Filmar)` next to an exercise to be preserved as a
   visible reminder in the builder, so that I remember which lifts my coach
   wants filmed.
9. As a lifter, I want `Dia 3) OFF/DESCANSO` to become a rest day with no
   planned sets (not be silently dropped), so that my day numbering (Dia 1,
   Dia 2, Dia 4...) still lines up with the source program.
10. As a lifter, I want exercises named "Agachamento", "Supino" (and
    variants like "Supino Inclinado", "Supino fechado"), and "Levantamento
    Terra" to be recognized as squat, bench press, and deadlift respectively,
    so that they're tracked as the competition lifts and show up in
    Analytics automatically.
11. As a lifter, I want any exercise the parser doesn't recognize as one of
    the big three (e.g. "Cadeira extensora", "Tríceps Pulley") to still be
    imported as a named accessory exercise, so that my full session — not
    just the competition lifts — is tracked.
12. As a lifter, I want a program to be labeled with its mesocycle and week
    number (e.g. "Mesociclo 2 · Semana 6"), so that I can tell which week
    I'm looking at when I have several weeks saved.
13. As a lifter with several weeks saved, I want the Programs list to show
    the mesocycle/week label alongside each program, so that I can pick the
    right one without opening each to check.
14. As a lifter, I want to still be able to build or edit a program entirely
    by hand through the existing builder, so that the paste-import path is
    additive, not a replacement for manual entry.
15. As a lifter pasting a program with a line the parser can't confidently
    classify, I want that line preserved as a note rather than silently
    dropped, so that I don't lose information I need to enter manually.
16. As a lifter, I want the 5/3/1 and Linear preset programs to be unaffected
    by any of this (no mesocycle/week label, no RPE sets), so that existing
    presets keep working exactly as they do today.

## Implementation Decisions

- **`LoadPrescription` gains an `.rpe(rpe: Double)` case** alongside the
  existing `.absolute(kg:)` and `.percentOfTrainingMax(percent:)`. Reps stay
  on `PlannedSet.targetReps` as they already do for the other two cases — the
  RPE case only carries the target RPE value, not a duplicate rep count.
  `LoadPrescription.resolvedKg(trainingMaxKg:)` changes its return type to
  `Double?`, returning `nil` for `.rpe` (there is no derivable weight — the
  lifter picks it in the moment to hit reps @ RPE). Both call sites
  (`PlannedSet.resolvedWeightKg`, and wherever a resolved weight currently
  feeds the Watch-bound envelope / history) need to handle `nil` explicitly
  rather than being force-unwrapped.

- **RPE weight resolution at send-time reuses the existing Session Override
  editor** (`SessionOverrideEditorView`), rather than adding a new screen:
  when the day being sent to the Watch contains any `.rpe` set, that set's
  weight field in the override editor has no prefilled value and must be
  filled in before Send is enabled — the same editable-envelope mechanism
  already used for ad-hoc weight bumps, just extended to require input
  instead of defaulting.

- **`PlannedSet` gains a `filmReminder: Bool` field** (default `false`),
  surfaced as a small badge/icon in the Program Builder's set list. Deliberately
  separate from `RawSetCapture` — this is a manual "remember to film" note
  parsed from `(Filmar)`, not related to the automatic IMU/HR raw-capture
  pipeline. Watch-side surfacing (a reminder chip on `LiveSetView`) is
  explicitly out of scope for v1 (see below).

- **`Program` gains optional `mesocycleNumber: Int?` and `weekNumber: Int?`**
  (both `nil` for programs not created via import, including the 5/3/1 and
  Linear presets — no behavior change for those). `ProgramsView`'s row shows
  "Mesociclo N · Semana M" as a subtitle when both are present. No new sort
  key — the list keeps sorting by `createdAt` as it does today.

- **Draft types move from the iOS app target into `SpottersaurusKit`.**
  `ProgramDraft` / `ProgramDayDraft` / `PlannedSetDraft` / `PlannedSetLoadDraft`
  currently live in `Spottersaurus/Features/Programs/Builder/ProgramDraft.swift`
  (app target only). The new parser must be pure and testable in the package,
  and must produce the same draft shape the existing builder UI already edits
  — so the draft types relocate into Kit (a pure refactor, no behavior
  change) and both the parser and the app-target builder UI reference the
  single relocated definition. This is the key seam: one draft model, not a
  parallel "parser output" shape that then has to be converted into the
  builder's draft shape.

- **New `ProgramImportParser`** (pure `String -> ProgramImportResult`, lives
  in `SpottersaurusKit`) recognizes, per day block:
  - the day header (`Dia N)`) and, for a block containing only
    `OFF`/`DESCANSO` (case-insensitive, PT or EN), emits an empty
    `ProgramDayDraft` rather than skipping the day;
  - an exercise name (first non-numeric line under a day), with a trailing
    parenthetical treated as a flag/note — `(Filmar)` sets `filmReminder`,
    anything else parenthetical (`(Convencional)`, `(pausa de 2s)`) is kept
    as free-text on the exercise;
  - a comma-separated set list per exercise where each token is one of:
    `weight/reps` (ramp step, e.g. `60/7`), `weightkg/reps reps xN sets`
    (e.g. `155kg/5reps x3sets`, expands to N identical `PlannedSetDraft`s),
    or `NxR@RPE(RPE)` (accessory shorthand, e.g. `4x12@9(RPE)`, expands to N
    identical RPE-based `PlannedSetDraft`s);
  - `Intervalo: <duration>` lines, applied to the nearest preceding
    exercise/set block, with a free-text duration parser handling `90s`,
    `2mins`, and range forms like `4-5mins` (upper bound converted to
    seconds).
  - Any line/token that doesn't match one of the above is preserved as a raw
    note attached to the nearest set or day rather than dropped or causing a
    hard parse failure — the parser is explicitly best-effort, and its output
    always opens in the editable builder for correction, never auto-saves.

- **Portuguese lift-name recognition**: "Agachamento" → `.squat`, "Supino"
  and its variants (Inclinado, fechado, etc.) → `.bench`, "Levantamento
  Terra" → `.deadlift`; anything else defaults to `.accessory` with the
  parsed name kept verbatim as the `Exercise.name`. This is the only mapping
  step needed for Analytics/History to pick up imported big-three sets —
  those views already key off `Exercise.kind`/`LiftKind`, unchanged.

## Testing Decisions

- `ProgramImportParser` is pure and gets exhaustive `Swift Testing` coverage
  in `SpottersaurusKitTests`, following the existing style in `ModelTests.swift`
  / `SessionOverrideTests.swift`. Cases: ramp-step expansion, `xN sets`
  expansion, RPE accessory expansion, `OFF`/`DESCANSO` day handling,
  `Intervalo` duration parsing (plain seconds, minutes, minute ranges,
  missing/malformed), PT lift-name variants mapping to the right `LiftKind`,
  and unrecognized lines surviving as notes instead of being dropped. The
  exact block pasted by the user in the sourcing conversation (Mesociclo
  2/Semana 6, 5 training days + 2 OFF days) becomes a golden-file regression
  fixture.
- `LoadPrescription.resolvedKg` is re-tested with the new `.rpe` case
  alongside the existing `.absolute`/`.percentOfTrainingMax` cases (nil
  result, no crash) — extends whatever existing coverage `ModelTests.swift`
  already has for `LoadPrescription`.
- The draft-type relocation (app target → Kit) is a pure refactor: existing
  builder previews/behavior are re-verified unchanged after the move, same
  as the precedent set by the Phase 0 Block F `@Observable` ViewModel
  conversions (`docs/TASKS.md`) — build-green + preview, not new tests, for
  the UI side.
- The paste-import screen and draft-review flow are UI-only: `#Preview` +
  build-green per house style (`docs/TASKS.md` Block F6/F7 precedent), no
  XCTest required for pure SwiftUI layout.

## Out of Scope

- PDF/photo OCR (Vision framework) — deferred. Paste-text covers the
  immediate need since most PDFs and spreadsheet exports are copy-pasteable
  as text.
- Structured spreadsheet/CSV import — deferred.
- A relational multi-week schema (a real `Week` entity nested under
  `Program`) — deferred in favor of the flat `Program` + optional
  mesocycle/week tag described above.
- Auto-progressing RPE-based accessory loads week over week (e.g.
  auto-suggesting next week's RPE-9 weight from logged history) — deferred;
  RPE sets always require the user to enter a weight at send-time.
- Watch-side surfacing of the film-reminder flag — v1 is iPhone-only
  (Builder list + Session Override editor). A Watch-side reminder chip is a
  natural follow-up, not required for this spec.
- Localizing the app's own UI into Portuguese — the parser understands
  Portuguese *input* vocabulary; the app interface itself stays English.

## Further Notes

- This directly unblocks tracking the three competition lifts (Agachamento /
  Supino / Levantamento Terra) from a real coach program, which is the
  concrete ask that motivated this spec — no new Analytics/History work is
  needed once the parser correctly tags `Exercise.kind`.
- Natural next step once this spec is approved: break it into `docs/backlog.md`
  tickets via `/to-tickets` (this repo's local ticket convention — see
  Phase 5 for the most recent example of that format).
