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
    @FocusState private var crownFocused: Bool

    init(plannedSet: PlannedSetEnvelope) {
        _viewModel = State(initialValue: LiveSetViewModel(plannedSet: plannedSet))
        _crownMode = State(initialValue: .load)
        _crownValue = State(initialValue: plannedSet.weightKg)
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
                        LiveSetHeaderView(
                            exerciseName: viewModel.exerciseName,
                            statusText: viewModel.statusText,
                            statusSymbol: viewModel.statusSymbol,
                            tone: viewModel.tone,
                            alertStage: viewModel.alertStage
                        )
                        HRAuthIndicatorView(status: viewModel.hrAuthStatus)
                        LiveSetRepGaugeView(
                            repCount: viewModel.repCount,
                            targetReps: viewModel.targetReps,
                            progress: viewModel.gaugeProgress,
                            tone: viewModel.tone,
                            alertStage: viewModel.alertStage
                        )
                        LiveSetMetricsGridView(
                            velocityMS: viewModel.velocityMS,
                            heartRate: viewModel.heartRate,
                            weightKg: viewModel.weightKg,
                            restText: viewModel.restText,
                            targetReps: viewModel.targetRepsText
                        )
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
            guard let restStartedAt else { return }
            let completed = viewModel.restTick(
                elapsed: now.timeIntervalSince(restStartedAt),
                logger: dependencies.logger
            )
            if completed {
                feedback.playRestCompleteCue()
                sendFinishedSessionIfAvailable()
                self.restStartedAt = nil
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

#Preview {
    LiveSetView(plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90))
}
