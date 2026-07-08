import SwiftData
import SpottersaurusKit

struct MaxesViewModel {
    private let competitionLifts: [LiftKind] = [.squat, .bench, .deadlift]

    func competitionMaxes(from maxes: [UserMaxes]) -> [UserMaxes] {
        competitionLifts.compactMap { lift in
            maxes.first { $0.lift == lift }
        }
    }

    func ensureCompetitionMaxesExist(in modelContext: ModelContext, existingMaxes: [UserMaxes]) {
        for lift in competitionLifts where !existingMaxes.contains(where: { $0.lift == lift }) {
            modelContext.insert(UserMaxes(lift: lift, trainingMaxKg: 0, oneRepMaxKg: 0))
        }
    }
}
