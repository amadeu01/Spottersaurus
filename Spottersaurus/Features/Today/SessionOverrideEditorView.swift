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
                    }
                    PrimaryButton("Send to Watch", systemImage: "applewatch", tint: Theme.Colors.brandOrange) {
                        Task { await send() }
                    }
                    .disabled(isSending)
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
