import SwiftUI
import Observation
import SpottersaurusKit

struct LiveSetView: View {
    @Environment(\.watchDependencies) private var dependencies
    @State private var viewModel: LiveSetViewModel
    @State private var sessionCoordinator = WatchLiveSessionCoordinator()
    @State private var feedback = WatchLiveSetFeedback()
    @State private var restStartedAt: Date?
    @State private var lastFeedbackAlertStage: AlertStage = .none
    @State private var crownMode: LiveSetCrownMode
    @State private var crownValue: Double
    @State private var handledCommandID: UUID?
    @State private var sessionStore = WatchPlannedSessionStore.shared
    /// Ticks once a second while armed/repping so `PipelineTelemetryView`
    /// reflects real elapsed staleness even when no new sample has arrived
    /// (that's the whole point of the readout — a stalled pipeline should
    /// visibly go stale, not freeze on its last good value).
    @State private var telemetryNow = Date()
    @FocusState private var crownFocused: Bool
    /// AOD calm variant (Phase 0.2 V1): the Watch runs inside an
    /// `HKWorkoutSession` during a set, so it stays frontmost and gets an
    /// Always-On Display when the wrist lowers — this must be a calm, static
    /// surface (no pulsing, no fast-churning decimals) for burn-in/battery.
    /// Gates presentation only; the RACK IT haptic/audio alarm path
    /// (`SetLifecycleController` / `WatchLiveSetFeedback`) is untouched and
    /// fires regardless of luminance.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// This set's zero-based position and the day's total set count — the
    /// "N"/"M" in "Set N of M" (Phase 0.2 M1b). `WatchRootView` recreates
    /// this view (via `.id(current.id)`) whenever the cursor moves to a
    /// different set, so these are safe to treat as fixed for this view's
    /// lifetime.
    let setIndex: Int
    let setCount: Int
    /// The set queued up after this one, if any — shown via
    /// `NextSetPreviewView` during rest so re-arming is a one-tap start.
    /// `nil` on the last set of the day.
    let nextSet: PlannedSetEnvelope?
    /// Called once this set has been racked AND its rest has fully elapsed
    /// (i.e. `viewModel.state == .complete`). `WatchRootView` wires this to
    /// `WatchDependencies.advanceSessionCursor`. Never fires on rack alone —
    /// only once the rest clock is actually done, matching the existing
    /// `.complete` gate that already allows re-arming.
    var onSetSessionComplete: () -> Void = {}

    init(
        plannedSet: PlannedSetEnvelope,
        setIndex: Int = 0,
        setCount: Int = 1,
        nextSet: PlannedSetEnvelope? = nil,
        onSetSessionComplete: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: LiveSetViewModel(plannedSet: plannedSet, setIndex: setIndex, setCount: setCount))
        _crownMode = State(initialValue: .load)
        _crownValue = State(initialValue: plannedSet.weightKg)
        self.setIndex = setIndex
        self.setCount = setCount
        self.nextSet = nextSet
        self.onSetSessionComplete = onSetSessionComplete
    }

    var body: some View {
        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            if viewModel.isRackItOverlayVisible {
                RackItOverlayView(resolveAlert: {
                    viewModel.resolveAlert()
                    lastFeedbackAlertStage = .none
                })
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.xs) {
                            PhoneConnectionChip(status: sessionStore.connectionStatus)
                            Spacer(minLength: Theme.Spacing.xs)
                            SetPositionBadgeView(setIndex: setIndex, setCount: setCount)
                        }
                        LiveSetHeaderView(
                            exerciseName: viewModel.exerciseName,
                            statusText: viewModel.statusText,
                            statusSymbol: viewModel.statusSymbol,
                            tone: viewModel.tone,
                            alertStage: viewModel.alertStage
                        )
                        HRAuthIndicatorView(status: viewModel.hrAuthStatus)
                        if !isLuminanceReduced, viewModel.state == .armed || viewModel.state == .repping {
                            // Hidden entirely on the Always-On Display: it's a
                            // dev/liveness micro-readout (sample rate + sample
                            // age) that would otherwise churn every second.
                            PipelineTelemetryView(
                                telemetry: viewModel.telemetry(sensorRunning: sessionCoordinator.isMotionRunning, now: telemetryNow)
                            )
                        }
                        LiveSetRepGaugeView(
                            repCount: viewModel.repCount,
                            targetReps: viewModel.targetReps,
                            progress: viewModel.gaugeProgress,
                            tone: viewModel.tone,
                            alertStage: viewModel.alertStage
                        )
                        LiveSetMetricsGridView(
                            velocityMS: viewModel.displayVelocityMS,
                            heartRate: viewModel.heartRate,
                            weightKg: viewModel.weightKg,
                            restText: viewModel.restText,
                            targetReps: viewModel.targetRepsText
                        )
                        if let nextSet, viewModel.state == .racked || viewModel.state == .resting {
                            NextSetPreviewView(nextSet: nextSet)
                        }
                        if viewModel.state == .idle || viewModel.state == .complete {
                            LiveSetCrownModeControlView(
                                mode: crownMode,
                                selectLoad: {
                                    crownMode = .load
                                    crownValue = viewModel.weightKg
                                },
                                selectReps: {
                                    crownMode = .reps
                                    crownValue = Double(viewModel.targetReps)
                                }
                            )
                        }
                        if viewModel.state == .idle || viewModel.state == .complete {
                            LiveSetCalibrationPanelView(
                                statusText: viewModel.calibrationStatusText,
                                detailText: "\(viewModel.calibrationDetailText) \(viewModel.sensorStatusText)",
                                progress: viewModel.calibrationProgress,
                                isCollecting: viewModel.isCalibrating,
                                start: {
                                    startWarmup()
                                },
                                finish: {
                                    viewModel.finishWarmupCalibration(logger: dependencies.logger)
                                    sessionCoordinator.stop(logger: dependencies.logger)
                                }
                            )
                        }
                        LiveSetControlsView(
                            state: viewModel.state,
                            arm: {
                                startWorkout()
                            },
                            completeRep: viewModel.completeRep,
                            flagGrinding: viewModel.flagGrinding,
                            rackIt: viewModel.rackIt,
                            rack: {
                                viewModel.rack(logger: dependencies.logger)
                                restStartedAt = Date()
                                sessionCoordinator.stop(logger: dependencies.logger)
                            },
                            finishRest: {
                                viewModel.finishRest(logger: dependencies.logger)
                                sessionCoordinator.stop(logger: dependencies.logger)
                                sendFinishedSessionIfAvailable()
                                restStartedAt = nil
                                onSetSessionComplete()
                            }
                        )
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .foregroundStyle(.white)
        .liveSetCrownRotation(
            enabled: crownEditingEnabled,
            value: $crownValue,
            mode: crownMode,
            focused: $crownFocused
        )
        .onChange(of: crownValue) { _, newValue in
            switch crownMode {
            case .load:
                viewModel.weightKg = newValue
            case .reps:
                viewModel.setTargetReps(newValue)
            }
        }
        .onChange(of: viewModel.alertStage) { _, newStage in
            playAlertFeedbackIfNeeded(newStage)
        }
        .onChange(of: dependencies.commandCenter().latestCommand?.id) { _, _ in
            handleLatestCommand()
        }
        .onChange(of: crownEditingEnabled) { _, isEnabled in
            crownFocused = isEnabled
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            telemetryNow = now
            guard let restStartedAt else { return }
            let completed = viewModel.restTick(
                elapsed: now.timeIntervalSince(restStartedAt),
                logger: dependencies.logger
            )
            if completed {
                feedback.playRestCompleteCue()
                sendFinishedSessionIfAvailable()
                self.restStartedAt = nil
                onSetSessionComplete()
            }
        }
        .onAppear {
            feedback = WatchLiveSetFeedback(logger: dependencies.logger)
            crownFocused = crownEditingEnabled
            handleLatestCommand()
            sessionCoordinator.refreshHRAuthStatus(viewModel: viewModel)
        }
        .onDisappear {
            sessionCoordinator.stop(logger: dependencies.logger)
        }
    }

    private var crownEditingEnabled: Bool {
        viewModel.state == .idle || viewModel.state == .complete
    }

    private func startWarmup() {
        guard viewModel.state == .idle || viewModel.state == .complete else { return }
        viewModel.startWarmupCalibration(logger: dependencies.logger)
        sessionCoordinator.start(
            viewModel: viewModel,
            logger: dependencies.logger,
            onLiveTick: dependencies.sendLiveTick
        )
    }

    private func startWorkout() {
        sessionCoordinator.stop(logger: dependencies.logger)
        viewModel.arm(logger: dependencies.logger)
        dependencies.sendLifecycle(
            .armed(
                lift: viewModel.lift,
                targetReps: viewModel.targetReps,
                weightKg: viewModel.weightKg,
                setIndex: setIndex,
                setCount: setCount
            )
        )
        sessionCoordinator.start(
            viewModel: viewModel,
            logger: dependencies.logger,
            onLiveTick: dependencies.sendLiveTick
        )
    }

    private func sendFinishedSessionIfAvailable() {
        guard let envelope = viewModel.finishedSessionEnvelope() else { return }
        dependencies.sendFinishedSession(envelope)
    }

    private func handleLatestCommand() {
        guard let command = dependencies.commandCenter().latestCommand,
              command.id != handledCommandID
        else { return }

        handledCommandID = command.id
        switch command.kind {
        case .startWarmup:
            startWarmup()
        case .startWorkout:
            startWorkout()
        }
    }

    private func playAlertFeedbackIfNeeded(_ stage: AlertStage) {
        guard stage != lastFeedbackAlertStage else { return }
        lastFeedbackAlertStage = stage
        switch stage {
        case .none:
            break
        case .grinding:
            feedback.playGrindingCue()
        case .rackIt:
            feedback.playRackItCue()
        }
    }
}

#if DEBUG
/// Preview-only progression states so `#Preview`s can show `LiveSetView`
/// already mid-set (armed/repping/grinding/RACK IT) without live sensor
/// input — needed to demonstrate the AOD calm variant (Phase 0.2 V1) beyond
/// the idle/pre-arm screen.
enum PreviewLiveSetState {
    case armed
    case repping(completedReps: Int)
    case grinding
    case rackIt
}

extension LiveSetView {
    init(
        plannedSet: PlannedSetEnvelope,
        previewState: PreviewLiveSetState,
        setIndex: Int = 0,
        setCount: Int = 1
    ) {
        let model = LiveSetViewModel(plannedSet: plannedSet, setIndex: setIndex, setCount: setCount)
        model.arm()
        switch previewState {
        case .armed:
            break
        case .repping(let completedReps):
            for _ in 0..<completedReps { model.completeRep() }
        case .grinding:
            model.completeRep()
            model.flagGrinding()
        case .rackIt:
            model.completeRep()
            model.rackIt()
        }
        _viewModel = State(initialValue: model)
        _crownMode = State(initialValue: .load)
        _crownValue = State(initialValue: plannedSet.weightKg)
        self.setIndex = setIndex
        self.setCount = setCount
        self.nextSet = nil
        self.onSetSessionComplete = {}
    }
}
#endif

private extension View {
    @ViewBuilder
    func liveSetCrownRotation(
        enabled: Bool,
        value: Binding<Double>,
        mode: LiveSetCrownMode,
        focused: FocusState<Bool>.Binding
    ) -> some View {
        if enabled {
            digitalCrownRotation(
                value,
                from: mode == .load ? 20 : 1,
                through: mode == .load ? 320 : 20,
                by: mode == .load ? 2.5 : 1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .focusable()
            .focused(focused)
        } else {
            self
        }
    }
}

#Preview("Idle") {
    LiveSetView(plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90))
}

#Preview("Repping") {
    LiveSetView(
        plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90),
        previewState: .repping(completedReps: 2)
    )
}

#Preview("AOD — Repping") {
    LiveSetView(
        plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90),
        previewState: .repping(completedReps: 2)
    )
    .environment(\.isLuminanceReduced, true)
}

#Preview("Grinding") {
    LiveSetView(
        plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90),
        previewState: .grinding
    )
}

#Preview("AOD — Grinding") {
    LiveSetView(
        plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90),
        previewState: .grinding
    )
    .environment(\.isLuminanceReduced, true)
}

#Preview("Rack It") {
    LiveSetView(
        plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90),
        previewState: .rackIt
    )
}

#Preview("AOD — Rack It") {
    LiveSetView(
        plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90),
        previewState: .rackIt
    )
    .environment(\.isLuminanceReduced, true)
}
