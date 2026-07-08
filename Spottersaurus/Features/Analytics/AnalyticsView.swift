import SwiftData
import SwiftUI
import SpottersaurusKit

struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]
    @State private var selectedLift: LiftKind = .bench

    private let viewModel = AnalyticsViewModel()

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

                    if records.isEmpty {
                        ContentUnavailableView(
                            "No Analytics",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Complete a Watch session to build trends.")
                        )
                    } else {
                        AnalyticsSummaryGridView(
                            bestE1RM: viewModel.bestEstimatedOneRepMax(from: records, lift: selectedLift),
                            totalTonnage: viewModel.totalTonnage(from: records),
                            spotterFrequency: viewModel.spotterFrequency(from: records, lift: selectedLift)
                        )

                        E1RMTrendChartView(points: viewModel.e1RMTrend(from: records, lift: selectedLift))
                        TonnageChartView(points: viewModel.tonnageSeries(from: records, lift: selectedLift))
                        VelocityLoadChartView(points: viewModel.velocityLoadPoints(from: records, lift: selectedLift))
                        SpotterFrequencyChartView(frequency: viewModel.spotterFrequency(from: records, lift: selectedLift))
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.canvas.opacity(0.04))
            .navigationTitle("Analytics")
            .refreshable {
                HistoryViewModel().refreshSavedSessionCount(in: modelContext)
            }
        }
    }

    private var records: [SetRecord] {
        viewModel.records(from: sessions)
    }
}

#Preview {
    AnalyticsView()
        .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
