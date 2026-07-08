import SwiftUI
import Observation
import SpottersaurusKit

struct LiveSetView: View {
    @State private var viewModel: LiveSetViewModel
    @State private var sessionCoordinator = WatchLiveSessionCoordinator()
    @FocusState private var crownFocused: Bool

    init(plannedSet: PlannedSetEnvelope) {
        _viewModel = State(initialValue: LiveSetViewModel(plannedSet: plannedSet))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            if viewModel.isRackItOverlayVisible {
                RackItOverlayView(resolveAlert: viewModel.resolveAlert)
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
                            restText: viewModel.restText
                        )
                        if viewModel.state == .idle || viewModel.state == .complete {
                            LiveSetCalibrationPanelView(
                                statusText: viewModel.calibrationStatusText,
                                detailText: viewModel.calibrationDetailText,
                                progress: viewModel.calibrationProgress,
                                isCollecting: viewModel.isCalibrating,
                                start: {
                                    viewModel.startWarmupCalibration()
                                    sessionCoordinator.startMotion(viewModel: viewModel)
                                },
                                finish: {
                                    viewModel.finishWarmupCalibration()
                                    sessionCoordinator.stop()
                                }
                            )
                        }
                        LiveSetControlsView(
                            state: viewModel.state,
                            arm: {
                                sessionCoordinator.stop()
                                viewModel.arm()
                                sessionCoordinator.start(viewModel: viewModel)
                            },
                            completeRep: viewModel.completeRep,
                            flagGrinding: viewModel.flagGrinding,
                            rackIt: viewModel.rackIt,
                            rack: {
                                viewModel.rack()
                                sessionCoordinator.stop()
                            },
                            finishRest: {
                                viewModel.finishRest()
                                sessionCoordinator.stop()
                            }
                        )
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.alertStage)
        .digitalCrownRotation(
            $viewModel.weightKg,
            from: 20,
            through: 320,
            by: 2.5,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .focusable()
        .focused($crownFocused)
        .onDisappear {
            sessionCoordinator.stop()
        }
    }
}

#Preview {
    LiveSetView(plannedSet: .init(lift: .bench, exerciseName: "Bench Press", targetReps: 5, weightKg: 100, restSeconds: 90))
}
