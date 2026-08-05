//
//  SessionOverrideEditorView.swift
//  Spottersaurus
//
//  Phase 0.2 M2 — the ephemeral per-send editor: bump/drop weight, change
//  reps/rest/AMRAP/lift for today's session before shipping it to the Watch.
//  See the "Session Override" glossary entry in `CONTEXT.md`.
//
//  IMPORTANT: this view never mutates the saved `Program`. It resolves the
//  base `PlannedSessionEnvelope` exactly once (in `init`, via
//  `.make(program:day:maxes:)` — a pure read of the SwiftData models, no
//  `modelContext` is even in scope here) and every subsequent edit only
//  touches the local `overrides` dictionary (`[UUID: SetOverride]`, keyed by
//  `PlannedSetEnvelope.id`) and the pure `SessionOverride.apply(to:)`
//  rewrite of that envelope copy. Nothing in this file can write back to
//  `Program`/`ProgramDay`/`PlannedSet`.
//

import SwiftUI
import SpottersaurusKit

struct SessionOverrideEditorView: View {
    @Environment(\.plannerDependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    /// Resolved once at init from the (unmodified) `Program`/`ProgramDay`/
    /// `UserMaxes` — never re-derived from a live model reference, so later
    /// edits to `overrides` can never leak back into SwiftData.
    private let baseEnvelope: PlannedSessionEnvelope
    @State private var overrides: [UUID: SetOverride] = [:]
    @State private var sendStatus: PlannedSessionSendStatus = .ready
    @State private var isSending = false

    init(program: Program, day: ProgramDay, maxes: [UserMaxes]) {
        self.baseEnvelope = PlannedSessionEnvelope.make(program: program, day: day, maxes: maxes)
    }

    /// The `SessionOverride` built from the current editor state — pure,
    /// re-derived on every read.
    private var override: SessionOverride {
        SessionOverride(setOverrides: overrides)
    }

    /// The envelope that would actually be sent right now.
    private var adjustedEnvelope: PlannedSessionEnvelope {
        override.apply(to: baseEnvelope)
    }

    /// `false` while any RPE-originated set in today's day (`PlannedSetEnvelope
    /// .requiresWeightInput`) still has no weight entered — "Send to Watch"
    /// stays disabled until every one of them is filled in. Non-RPE sets are
    /// never gated. See the "RPE weight resolution at send-time"
    /// Implementation Decision in `docs/specs/2026-08-05-custom-program-import.md`.
    private var canSend: Bool {
        !override.hasUnfilledRequiredWeights(in: baseEnvelope)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(baseEnvelope.programName)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(baseEnvelope.dayName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(baseEnvelope.sets) { set in
                        SessionOverrideSetCard(set: set, override: overrideBinding(for: set))
                    }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.canvas.opacity(0.04))
            .navigationTitle("Adjust Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.sm) {
                    if sendStatus != .ready {
                        Text(sendStatus.rawValue)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } else if !canSend {
                        Text("Enter a weight for every RPE set before sending.")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.Colors.brandOrange)
                    }
                    PrimaryButton("Send to Watch", systemImage: "applewatch", tint: Theme.Colors.brandOrange) {
                        Task { await send() }
                    }
                    .disabled(isSending || !canSend)
                }
                .padding(Theme.Spacing.md)
                .background(.ultraThinMaterial)
            }
        }
    }

    @MainActor
    private func send() async {
        isSending = true
        sendStatus = await dependencies.sendPlannedSessionEnvelopeToWatch(adjustedEnvelope)
        isSending = false
        if sendStatus == .sent || sendStatus == .queued {
            dismiss()
        }
    }

    /// A two-way binding into `overrides[set.id]`, defaulting to `.empty`
    /// (identity) when no edit has been made for this set yet.
    private func overrideBinding(for set: PlannedSetEnvelope) -> Binding<SetOverride> {
        Binding(
            get: { overrides[set.id] ?? .empty },
            set: { overrides[set.id] = $0 }
        )
    }
}

/// One editable set row: lift picker, target reps / weight / rest steppers,
/// and an AMRAP toggle. Reads the base set's values as the fallback for any
/// field the override hasn't touched yet.
private struct SessionOverrideSetCard: View {
    var set: PlannedSetEnvelope
    @Binding var override: SetOverride

    private var liftBinding: Binding<LiftKind> {
        Binding(get: { override.lift ?? set.lift }, set: { override.lift = $0 })
    }

    private var targetRepsBinding: Binding<Int> {
        Binding(get: { override.targetReps ?? set.targetReps }, set: { override.targetReps = $0 })
    }

    private var weightBinding: Binding<Double> {
        Binding(get: { override.weightKg ?? set.weightKg }, set: { override.weightKg = $0 })
    }

    /// Text-field binding for an RPE-originated set's weight: unlike
    /// `weightBinding`, this never falls back to `set.weightKg` (that's just
    /// the `0` placeholder `Progression.resolvedWeightKg` uses for RPE loads —
    /// see `PlannedSetEnvelope.requiresWeightInput`) — the field starts truly
    /// empty and only reflects a value once the lifter types one in.
    private var rpeWeightTextBinding: Binding<String> {
        Binding(
            get: {
                guard let weightKg = override.weightKg else { return "" }
                return weightKg.formatted(.number.precision(.fractionLength(0...2)))
            },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                override.weightKg = Double(normalized)
            }
        )
    }

    private var restBinding: Binding<Int> {
        Binding(get: { override.restSeconds ?? set.restSeconds }, set: { override.restSeconds = $0 })
    }

    private var amrapBinding: Binding<Bool> {
        Binding(get: { override.isAMRAP ?? set.isAMRAP }, set: { override.isAMRAP = $0 })
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Picker("Lift", selection: liftBinding) {
                    ForEach(LiftKind.allCases) { lift in
                        Text(lift.displayName).tag(lift)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(.body, design: .rounded, weight: .bold))
                .frame(minHeight: 44, alignment: .leading)

                Stepper(value: targetRepsBinding, in: 1...30) {
                    HStack {
                        Text("Reps")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(targetRepsBinding.wrappedValue)")
                            .monospacedDigit()
                    }
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(minHeight: 44)

                if set.requiresWeightInput {
                    // RPE-prescribed set: no derivable weight to prefill (see
                    // `PlannedSetEnvelope.requiresWeightInput`) — the field
                    // starts empty and "Send to Watch" stays disabled until
                    // it's filled in.
                    HStack {
                        Text("Weight")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Enter weight", text: rpeWeightTextBinding)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.brandOrange)
                            .frame(minWidth: 80)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(minHeight: 44)
                } else {
                    Stepper(value: weightBinding, in: 0...500, step: 2.5) {
                        HStack {
                            Text("Weight")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(weightBinding.wrappedValue.formatted(.number.precision(.fractionLength(0...1)))) kg")
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.brandOrange)
                        }
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(minHeight: 44)
                }

                Stepper(value: restBinding, in: 0...600, step: 15) {
                    HStack {
                        Text("Rest")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(restBinding.wrappedValue)s")
                            .monospacedDigit()
                    }
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(minHeight: 44)

                Toggle("AMRAP", isOn: amrapBinding)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(minHeight: 44)
            }
        }
    }
}

#Preview("Multi-set session") {
    let maxes = PreviewSeed.maxes()
    let program = PreviewSeed.program(maxes: maxes)

    return SessionOverrideEditorView(program: program, day: program.orderedDays[0], maxes: maxes)
}

/// A day mixing a fixed-load main lift with RPE-prescribed accessory work —
/// covers Issue #6: the RPE set's weight field starts empty (no prefilled
/// value) while the fixed-load set still prefills as normal, and "Send to
/// Watch" starts disabled until the RPE set's weight is entered.
#Preview("RPE mix — weight required before Send") {
    let bench = Exercise(name: "Bench Press", kind: .bench)
    let flye = Exercise(name: "Cable Fly", kind: .accessory)
    let extension_ = Exercise(name: "Triceps Pulley", kind: .accessory)

    let program = Program(name: "Coach Block", rule: .custom, mesocycleNumber: 2, weekNumber: 6)
    let day = ProgramDay(name: "Dia 2 — Peito")
    day.plannedSets = [
        PlannedSet(exercise: bench, targetReps: 5, load: .absolute(kg: 100), restSeconds: 180, sortIndex: 0),
        PlannedSet(exercise: flye, targetReps: 12, load: .rpe(rpe: 9), restSeconds: 90, sortIndex: 1),
        PlannedSet(exercise: extension_, targetReps: 12, load: .rpe(rpe: 8), restSeconds: 60, sortIndex: 2),
    ]
    program.days = [day]

    return SessionOverrideEditorView(program: program, day: day, maxes: [])
}
