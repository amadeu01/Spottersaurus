//
//  ProgramDraft.swift
//  SpottersaurusKit
//
//  In-memory, editable draft mirror of the `Program` graph. The iOS program
//  builder mutates these value types freely (bindings, undo-free editing)
//  and only materializes real `@Model` objects via `makeProgram()` once the
//  user saves. Living here (rather than in the app target) lets a future
//  parser construct drafts from imported program text and be unit-tested
//  with `swift test`, without depending on the app target.
//

import Foundation

/// A draft program: name, progression rule, and an ordered list of draft
/// days. Mirrors `Program` but stays a plain value type until `makeProgram()`
/// is called.
public struct ProgramDraft: Identifiable {
    public var id = UUID()
    public var name = "Custom Program"
    public var rule: ProgressionRule = .custom
    public var days: [ProgramDayDraft] = [
        ProgramDayDraft(name: "Day 1"),
    ]
    /// Optional mesocycle label, parsed from an imported coach block (e.g.
    /// "Mesociclo 2"). `nil` for programs not created via import.
    public var mesocycleNumber: Int?
    /// Optional week-within-mesocycle label (e.g. "Semana 6"), paired with
    /// `mesocycleNumber`. `nil` for programs not created via import.
    public var weekNumber: Int?

    public init(
        id: UUID = UUID(),
        name: String = "Custom Program",
        rule: ProgressionRule = .custom,
        days: [ProgramDayDraft] = [ProgramDayDraft(name: "Day 1")],
        mesocycleNumber: Int? = nil,
        weekNumber: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.rule = rule
        self.days = days
        self.mesocycleNumber = mesocycleNumber
        self.weekNumber = weekNumber
    }

    /// Trims the name and normalizes each day (falling back to "Day N" for
    /// blank day names).
    public func normalized() -> ProgramDraft {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.days = copy.days.enumerated().map { index, day in
            day.normalized(fallbackName: "Day \(index + 1)")
        }
        return copy
    }

    /// Materializes a real `Program` graph (with `Exercise`, `ProgramDay`,
    /// `PlannedSet` objects) from this draft. Days with no sets are skipped.
    public func makeProgram() -> Program {
        let normalized = normalized()
        let program = Program(
            name: normalized.name,
            rule: normalized.rule,
            mesocycleNumber: normalized.mesocycleNumber,
            weekNumber: normalized.weekNumber
        )
        for (dayIndex, dayDraft) in normalized.days.enumerated() where !dayDraft.sets.isEmpty {
            let day = ProgramDay(name: dayDraft.name, sortIndex: dayIndex)
            for (setIndex, setDraft) in dayDraft.sets.enumerated() {
                let exercise = Exercise(name: setDraft.exerciseName, kind: setDraft.lift)
                let set = PlannedSet(
                    exercise: exercise,
                    targetReps: setDraft.targetReps,
                    load: setDraft.load.prescription,
                    isAMRAP: setDraft.isAMRAP,
                    restSeconds: setDraft.restSeconds,
                    filmReminder: setDraft.filmReminder,
                    sortIndex: setIndex
                )
                day.appendPlannedSet(set)
            }
            program.appendDay(day)
        }
        return program
    }
}

/// A draft program day: a name and an ordered list of draft planned sets.
public struct ProgramDayDraft: Identifiable {
    public var id = UUID()
    public var name: String
    public var sets: [PlannedSetDraft] = [PlannedSetDraft()]

    public init(id: UUID = UUID(), name: String, sets: [PlannedSetDraft] = [PlannedSetDraft()]) {
        self.id = id
        self.name = name
        self.sets = sets
    }

    /// Trims the name, falling back to `fallbackName` when blank, and
    /// normalizes each set.
    public func normalized(fallbackName: String) -> ProgramDayDraft {
        var copy = self
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? fallbackName : trimmed
        copy.sets = copy.sets.map { $0.normalized() }
        return copy
    }
}

/// A draft planned set: lift, exercise name override, reps, load, AMRAP, and
/// rest.
public struct PlannedSetDraft: Identifiable {
    public var id = UUID()
    public var lift: LiftKind = .squat
    public var customExerciseName = ""
    public var targetReps = 5
    public var load = PlannedSetLoadDraft(kind: .absolute, value: 100)
    public var isAMRAP = false
    public var restSeconds = 180
    /// Manual "remember to film this set" reminder, parsed from coach
    /// shorthand `(Filmar)`.
    public var filmReminder = false

    public init(
        id: UUID = UUID(),
        lift: LiftKind = .squat,
        customExerciseName: String = "",
        targetReps: Int = 5,
        load: PlannedSetLoadDraft = PlannedSetLoadDraft(kind: .absolute, value: 100),
        isAMRAP: Bool = false,
        restSeconds: Int = 180,
        filmReminder: Bool = false
    ) {
        self.id = id
        self.lift = lift
        self.customExerciseName = customExerciseName
        self.targetReps = targetReps
        self.load = load
        self.isAMRAP = isAMRAP
        self.restSeconds = restSeconds
        self.filmReminder = filmReminder
    }

    /// The exercise name to store: the custom name for accessory work when
    /// provided, otherwise the lift's display name.
    public var exerciseName: String {
        let trimmed = customExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if lift == .accessory && !trimmed.isEmpty {
            return trimmed
        }
        return lift.displayName
    }

    /// Clamps reps/rest/load to sane floors and trims the custom exercise
    /// name.
    public func normalized() -> PlannedSetDraft {
        var copy = self
        copy.targetReps = max(1, copy.targetReps)
        copy.restSeconds = max(30, copy.restSeconds)
        copy.load.value = max(0, copy.load.value)
        copy.customExerciseName = copy.customExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

/// A draft planned-set load: either an absolute weight or a percent of
/// training max, editable as a single numeric `value` alongside its `kind`.
public struct PlannedSetLoadDraft: Equatable {
    public enum Kind: String, CaseIterable, Identifiable {
        case absolute
        case percentOfTrainingMax
        /// A target RPE (rate of perceived exertion); `value` carries the RPE
        /// number, not a weight. See `LoadPrescription.rpe`.
        case rpe

        public var id: String { rawValue }
    }

    public var kind: Kind
    public var value: Double

    public init(kind: Kind, value: Double) {
        self.kind = kind
        self.value = value
    }

    /// Resolves to a real `LoadPrescription` for `makeProgram()`.
    public var prescription: LoadPrescription {
        switch kind {
        case .absolute:
            return .absolute(kg: value)
        case .percentOfTrainingMax:
            return .percentOfTrainingMax(percent: value)
        case .rpe:
            return .rpe(rpe: value)
        }
    }

    /// A short human-readable summary, e.g. "100.0 kg", "85% training max", or
    /// "RPE 9".
    public var summary: String {
        switch kind {
        case .absolute:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) kg"
        case .percentOfTrainingMax:
            return "\(Int(value))% training max"
        case .rpe:
            return "RPE \(value.formatted(.number.precision(.fractionLength(0...1))))"
        }
    }
}
