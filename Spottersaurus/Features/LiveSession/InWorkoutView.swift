//
//  InWorkoutView.swift
//  Spottersaurus
//
//  The iPhone's app-wide, dismissible full-screen takeover for an active Live
//  Session (Phase 0.2 S1 — see `docs/adr/0001-live-session-surfaces-and-transport.md`
//  and the "In-Workout View" / "Live Session" glossary entries in
//  `CONTEXT.md`). This is the phone MIRROR of the Watch's live set screen —
//  informational only. The Watch remains the real-time instrument and the
//  safety alarm; nothing here is safety-critical, so a stale/absent metric
//  just renders a placeholder rather than guessing.
//
//  Presented from `ContentView` (see the `.fullScreenCover` call site there),
//  driven by `LiveSessionMonitor.shared`.
//
//  Deliberately takes `phase` / `identity` / `metrics` as plain parameters
//  rather than the whole `LiveSessionMonitor` (or `LiveSessionState`), so
//  every phase — including `.resting`, which the current `LiveSessionState`
//  reducer cannot yet produce (real rest tracking lands with M1's multi-set
//  Watch cursor) — is directly previewable without reaching into the
//  reducer's `private(set)` internals from outside its own file.
//

import SwiftUI
import SpottersaurusKit

struct InWorkoutView: View {
    var phase: LiveSessionState.Phase
    var identity: LiveSessionState.Identity?
    var metrics: LiveSessionState.Metrics?
    /// Invoked when the lifter dismisses the takeover (drag-down or the close
    /// button) — the Live Set keeps running on the Watch; only this iPhone
    /// surface backs off. `ContentView` re-presents it via the "return to
    /// set" pill.
    var onClose: () -> Void

    /// How far past the drag threshold counts as an intentional dismiss.
    private static let dismissDragThreshold: CGFloat = 120

    @State private var dragOffset: CGFloat = 0

    private var alertStage: AlertStage {
        metrics?.alertStage ?? .none
    }

    private var tint: Color {
        switch alertStage {
        case .none: Theme.Colors.optimal
        case .grinding: Theme.Colors.caution
        case .rackIt: Theme.Colors.alert
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                dragHandle
                header

                Spacer(minLength: Theme.Spacing.sm)

                repRing

                alertBanner

                metricsCard

                if phase == .resting {
                    restCard
                }

                Spacer(minLength: Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
        }
        .foregroundStyle(.white)
        .offset(y: max(dragOffset, 0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = max(value.translation.height, 0)
                }
                .onEnded { value in
                    if value.translation.height > Self.dismissDragThreshold {
                        onClose()
                    }
                    dragOffset = 0
                }
        )
        .animation(.easeOut, value: alertStage)
        .animation(.interactiveSpring, value: dragOffset)
    }

    // MARK: Chrome

    private var dragHandle: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.3))
                .frame(width: 40, height: 5)

            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(.title2, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Dismiss live set view")
            }
            .padding(.trailing, -Theme.Spacing.sm)
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let identity {
                Text("SET \(identity.setIndex + 1) OF \(identity.setCount)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))

                Text(identity.lift.displayName)
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))

                Text("\(identity.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            } else {
                Text("LIVE SESSION")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Waiting for the Watch…")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
            }
        }
    }

    // MARK: Reps

    private var repRing: some View {
        let reps = metrics?.repCount ?? 0
        let target = identity?.targetReps ?? 0
        let progress = target > 0 ? Double(reps) / Double(target) : 0

        return RingGauge(progress: progress, tint: tint, lineWidth: 18) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("\(reps)")
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(target > 0 ? "of \(target) reps" : "reps")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 220, height: 220)
    }

    // MARK: Alert Stage

    @ViewBuilder
    private var alertBanner: some View {
        switch alertStage {
        case .none:
            EmptyView()
        case .grinding:
            alertLabel("GRINDING", symbol: "exclamationmark.triangle.fill")
        case .rackIt:
            alertLabel("RACK IT", symbol: "hand.raised.fill")
        }
    }

    private func alertLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(.title3, design: .rounded, weight: .heavy))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Capsule(style: .continuous).fill(tint))
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: Metrics

    private var metricsCard: some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.lg) {
                MetricReadout(
                    label: "Mean Concentric Velocity",
                    value: (metrics?.meanConcentricVelocityMS ?? 0).formatted(.number.precision(.fractionLength(2))),
                    unit: "m/s"
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .overlay(.white.opacity(0.15))

                MetricReadout(
                    label: "Heart Rate",
                    value: metrics.map { "\(Int($0.heartRateBPM))" } ?? "--",
                    unit: "bpm"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Rest

    /// A rotating (indeterminate) rest ring shown while `.resting`. There is
    /// no rest-duration data on the wire yet (that lands with M1's multi-set
    /// rest tracking), so this deliberately never fakes a countdown — an
    /// honest "resting" state beats a made-up number.
    private var restCard: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.sm) {
                TimelineView(.animation) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let rotation = (now.truncatingRemainder(dividingBy: 1.6)) / 1.6 * 360

                    RingGauge(progress: 0.3, tint: Theme.Colors.optimal, lineWidth: 10) {
                        Image(systemName: "hourglass")
                            .font(.system(.title2, weight: .bold))
                    }
                    .rotationEffect(.degrees(rotation))
                    .frame(width: 96, height: 96)
                }

                Text("RESTING")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text("Get ready for your next set.")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Theme.Colors.canvas
            tint.opacity(alertStage == .none ? 0 : 0.22)
        }
    }
}

#Preview("Active mid-set") {
    InWorkoutView(
        phase: .active,
        identity: .init(lift: .bench, targetReps: 5, weightKg: 100, setIndex: 1, setCount: 4),
        metrics: .init(
            repCount: 3,
            meanConcentricVelocityMS: 0.42,
            heartRateBPM: 132,
            alertStage: .none,
            elapsedSeconds: 18,
            setIndex: 1,
            setCount: 4
        ),
        onClose: {}
    )
}

#Preview("Grinding (amber)") {
    InWorkoutView(
        phase: .active,
        identity: .init(lift: .squat, targetReps: 5, weightKg: 140, setIndex: 2, setCount: 4),
        metrics: .init(
            repCount: 4,
            meanConcentricVelocityMS: 0.18,
            heartRateBPM: 158,
            alertStage: .grinding,
            elapsedSeconds: 41,
            setIndex: 2,
            setCount: 4
        ),
        onClose: {}
    )
}

#Preview("Rack it (red)") {
    InWorkoutView(
        phase: .active,
        identity: .init(lift: .squat, targetReps: 5, weightKg: 140, setIndex: 2, setCount: 4),
        metrics: .init(
            repCount: 4,
            meanConcentricVelocityMS: 0.04,
            heartRateBPM: 171,
            alertStage: .rackIt,
            elapsedSeconds: 52,
            setIndex: 2,
            setCount: 4
        ),
        onClose: {}
    )
}

#Preview("Resting (rest ring)") {
    InWorkoutView(
        phase: .resting,
        identity: .init(lift: .bench, targetReps: 5, weightKg: 100, setIndex: 1, setCount: 4),
        metrics: .init(
            repCount: 5,
            meanConcentricVelocityMS: 0.31,
            heartRateBPM: 124,
            alertStage: .none,
            elapsedSeconds: 96,
            setIndex: 1,
            setCount: 4
        ),
        onClose: {}
    )
}

#Preview("Waiting for identity") {
    InWorkoutView(phase: .active, identity: nil, metrics: nil, onClose: {})
}
