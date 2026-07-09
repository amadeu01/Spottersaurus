import SwiftData
import SwiftUI
import SpottersaurusKit

struct AnalyticsView: View {
    @Query private var sessions: [WorkoutSession]
    @State private var selectedLift: LiftKind = .bench

    @State private var viewModel = AnalyticsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Picker("Lift", selection: $selectedLift) {
                        ForEach(LiftKind.allCases.filter { $0 != .accessory }) { lift in
                            Text(lift.displayName).tag(lift)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.records.isEmpty {
                        ContentUnavailableView(
                            "No Analytics",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Complete a Watch session to build trends.")
                        )
                    } else {
                        AnalyticsSummaryGridView(
                            bestE1RM: viewModel.bestEstimatedOneRepMax(lift: selectedLift),
                            totalTonnage: viewModel.totalTonnage(),
                            spotterFrequency: viewModel.spotterFrequency(lift: selectedLift)
                        )

                        E1RMTrendChartView(points: viewModel.e1RMTrend(lift: selectedLift))
                        TonnageChartView(points: viewModel.tonnageSeries(lift: selectedLift))
                        VelocityLoadChartView(points: viewModel.velocityLoadPoints(lift: selectedLift))
                        SpotterFrequencyChartView(frequency: viewModel.spotterFrequency(lift: selectedLift))
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.canvas.opacity(0.04))
            .navigationTitle("Analytics")
            .onChange(of: sessions, initial: true) { _, newValue in
                viewModel.update(with: newValue)
            }
        }
    }
}

#Preview {
    AnalyticsView()
        .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
