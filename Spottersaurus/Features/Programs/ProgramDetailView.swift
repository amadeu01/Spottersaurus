import SwiftData
import SwiftUI
import SpottersaurusKit

struct ProgramDetailView: View {
    var program: Program
    var maxes: [UserMaxes]

    var body: some View {
        List {
            ForEach(program.orderedDays) { day in
                Section(day.name) {
                    ForEach(day.orderedSets) { set in
                        PlannedSetRow(set: set, maxes: maxes)
                    }
                }
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let maxes = PreviewSeed.maxes()
    let program = PreviewSeed.program(maxes: maxes)

    return NavigationStack {
        ProgramDetailView(program: program, maxes: maxes)
    }
    .modelContainer(try! makeModelContainer(inMemory: true, cloudKit: false))
}
