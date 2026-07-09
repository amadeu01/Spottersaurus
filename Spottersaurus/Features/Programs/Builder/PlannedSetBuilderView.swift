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
        }
    }

    private var restText: String {
        let minutes = set.restSeconds / 60
        let seconds = set.restSeconds % 60
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }
}

#Preview {
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
