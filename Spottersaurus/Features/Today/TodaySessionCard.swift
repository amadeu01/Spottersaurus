import SwiftUI
import SpottersaurusKit

struct TodaySessionCard: View {
    var program: Program
    var day: ProgramDay
    var maxes: [UserMaxes]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(program.name)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(day.name)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(day.orderedSets) { set in
                        PlannedSetRow(set: set, maxes: maxes)
                    }
                }
            }
        }
    }
}
