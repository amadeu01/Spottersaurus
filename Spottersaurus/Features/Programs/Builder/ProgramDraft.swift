import Foundation
import SpottersaurusKit

struct ProgramDraft: Identifiable {
    var id = UUID()
    var name = "Custom Program"
    var rule: ProgressionRule = .custom
    var days: [ProgramDayDraft] = [
        ProgramDayDraft(name: "Day 1"),
    ]

    func normalized() -> ProgramDraft {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.days = copy.days.enumerated().map { index, day in
            day.normalized(fallbackName: "Day \(index + 1)")
        }
        return copy
    }

    func makeProgram() -> Program {
        let normalized = normalized()
        let program = Program(name: normalized.name, rule: normalized.rule)
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
                    sortIndex: setIndex
                )
                day.appendPlannedSet(set)
            }
            program.appendDay(day)
        }
        return program
    }
}

struct ProgramDayDraft: Identifiable {
    var id = UUID()
    var name: String
    var sets: [PlannedSetDraft] = [PlannedSetDraft()]

    func normalized(fallbackName: String) -> ProgramDayDraft {
        var copy = self
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? fallbackName : trimmed
        copy.sets = copy.sets.map { $0.normalized() }
        return copy
    }
}

struct PlannedSetDraft: Identifiable {
    var id = UUID()
    var lift: LiftKind = .squat
    var customExerciseName = ""
    var targetReps = 5
    var load = PlannedSetLoadDraft(kind: .absolute, value: 100)
    var isAMRAP = false
    var restSeconds = 180

    var exerciseName: String {
        let trimmed = customExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if lift == .accessory && !trimmed.isEmpty {
            return trimmed
        }
        return lift.displayName
    }

    func normalized() -> PlannedSetDraft {
        var copy = self
        copy.targetReps = max(1, copy.targetReps)
        copy.restSeconds = max(30, copy.restSeconds)
        copy.load.value = max(0, copy.load.value)
        copy.customExerciseName = copy.customExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

struct PlannedSetLoadDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case absolute
        case percentOfTrainingMax

        var id: String { rawValue }
    }

    var kind: Kind
    var value: Double

    var prescription: LoadPrescription {
        switch kind {
        case .absolute:
            return .absolute(kg: value)
        case .percentOfTrainingMax:
            return .percentOfTrainingMax(percent: value)
        }
    }

    var summary: String {
        switch kind {
        case .absolute:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) kg"
        case .percentOfTrainingMax:
            return "\(Int(value))% training max"
        }
    }
}
