import SwiftUI
import SpottersaurusKit

struct PlannedSetBuilderView: View {
    @Binding var set: PlannedSetDraft

    var body: some View {
        Form {
            Section("Exercise") {
                Picker("Lift", selection: $set.lift) {
                    ForEach(LiftKind.allCases) { lift in
                        Text(lift.displayName).tag(lift)
                    }
                }

                if set.lift == .accessory {
                    TextField("Exercise Name", text: $set.customExerciseName)
                }
            }

            Section("Prescription") {
                Stepper(value: $set.targetReps, in: 1...50) {
                    HStack {
                        Text("Target Reps")
                        Spacer()
                        Text("\(set.targetReps)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("AMRAP", isOn: $set.isAMRAP)

                Picker("Load", selection: $set.load.kind) {
                    Text("Weight").tag(PlannedSetLoadDraft.Kind.absolute)
                    Text("% Training Max").tag(PlannedSetLoadDraft.Kind.percentOfTrainingMax)
                    Text("RPE").tag(PlannedSetLoadDraft.Kind.rpe)
                }
                .pickerStyle(.segmented)

                loadEditor

                Stepper(value: $set.restSeconds, in: 30...600, step: 15) {
                    HStack {
                        Text("Rest")
                        Spacer()
                        Text(restText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle(isOn: $set.filmReminder) {
                    Label("Film This Set", systemImage: "video.fill")
                }
            }
        }
        .navigationTitle(set.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var loadEditor: some View {
        switch set.load.kind {
        case .absolute:
            Stepper(value: $set.load.value, in: 0...500, step: 2.5) {
                HStack {
                    Text("Weight")
                    Spacer()
                    Text("\(set.load.value.formatted(.number.precision(.fractionLength(0...1)))) kg")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        case .percentOfTrainingMax:
            Stepper(value: $set.load.value, in: 0...150, step: 5) {
                HStack {
                    Text("Percent")
                    Spacer()
                    Text("\(Int(set.load.value))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        case .rpe:
            Stepper(value: $set.load.value, in: 1...10, step: 0.5) {
                HStack {
                    Text("Target RPE")
                    Spacer()
                    Text(set.load.value.formatted(.number.precision(.fractionLength(0...1))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var restText: String {
        let minutes = set.restSeconds / 60
        let seconds = set.restSeconds % 60
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }
}

#Preview("Percent of Training Max") {
    @Previewable @State var set = PlannedSetDraft(
        lift: .bench,
        targetReps: 5,
        load: PlannedSetLoadDraft(kind: .percentOfTrainingMax, value: 85),
        isAMRAP: true
    )

    return NavigationStack {
        PlannedSetBuilderView(set: $set)
    }
}

#Preview("RPE Load") {
    @Previewable @State var set = PlannedSetDraft(
        lift: .accessory,
        customExerciseName: "Leg Press",
        targetReps: 12,
        load: PlannedSetLoadDraft(kind: .rpe, value: 9)
    )

    return NavigationStack {
        PlannedSetBuilderView(set: $set)
    }
}

#Preview("Film Reminder") {
    @Previewable @State var set = PlannedSetDraft(
        lift: .squat,
        targetReps: 5,
        load: PlannedSetLoadDraft(kind: .absolute, value: 140),
        filmReminder: true
    )

    return NavigationStack {
        PlannedSetBuilderView(set: $set)
    }
}
