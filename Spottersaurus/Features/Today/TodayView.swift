import SwiftData
import SwiftUI
import SpottersaurusKit

struct TodayView: View {
    @Environment(\.plannerDependencies) private var dependencies
    @Query private var programs: [Program]
    @Query private var maxes: [UserMaxes]
    @State private var viewModel = TodayViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    if let program = viewModel.activeProgram(from: programs),
                       let day = viewModel.todaysProgramDay(in: program) {
                        TodaySessionCard(program: program, day: day, maxes: maxes)
                        PrimaryButton("Send to Watch", systemImage: "applewatch", tint: Theme.Colors.brandOrange) {
                            Task {
                                await viewModel.sendPlannedSession(program: program, day: day, maxes: maxes, using: dependencies)
                            }
                        }
                        Text(viewModel.sendStatus.rawValue)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        EmptyPlannerStateView()
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.canvas.opacity(0.04))
            .navigationTitle("Today")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Spottersaurus")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
