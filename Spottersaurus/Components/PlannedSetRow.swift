import SwiftUI
import SpottersaurusKit

struct PlannedSetRow: View {
    var set: PlannedSet
    var maxes: [UserMaxes]

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.exercise?.name ?? "Lift")
                    .font(.system(.body, design: .rounded, weight: .bold))
                Text(restText)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(repsText)
                    .font(.system(.body, design: .rounded, weight: .heavy))
                    .monospacedDigit()
                Text(loadText)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.Colors.brandOrange)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var repsText: String {
        return set.isAMRAP ? "\(set.targetReps)+" : "\(set.targetReps)"
    }

    private var restText: String {
        return "Rest \(set.restSeconds / 60)m"
    }

    private var loadText: String {
        let kg = Progression.resolvedWeightKg(for: set, maxes: maxes)
        switch set.load {
        case .absolute:
            return "\(kg.formatted(.number.precision(.fractionLength(0...1)))) kg"
        case .percentOfTrainingMax(let percent):
            return "\(Int(percent))% · \(kg.formatted(.number.precision(.fractionLength(0...1)))) kg"
        }
    }
}

#Preview {
    let maxes = PreviewSeed.maxes()
    let squat = PlannedSet(
        exercise: Exercise(name: "Back Squat", kind: .squat),
        targetReps: 5,
        load: .percentOfTrainingMax(percent: 85),
        isAMRAP: true,
        restSeconds: 180
    )
    let bench = PlannedSet(
        exercise: Exercise(name: "Bench Press", kind: .bench),
        targetReps: 8,
        load: .absolute(kg: 60),
        restSeconds: 90
    )

    return List {
        PlannedSetRow(set: squat, maxes: maxes)
        PlannedSetRow(set: bench, maxes: maxes)
    }
}
