import Foundation
import Observation
import SpottersaurusKit

@Observable
final class TodayViewModel {
    var sendStatus: PlannedSessionSendStatus = .ready

    func activeProgram(from programs: [Program]) -> Program? {
        programs.sorted { $0.createdAt > $1.createdAt }.first
    }

    func todaysProgramDay(in program: Program, date: Date = Date()) -> ProgramDay? {
        let days = program.orderedDays
        guard !days.isEmpty else { return nil }
        let weekday = Calendar.current.component(.weekday, from: date)
        return days[(weekday - 1) % days.count]
    }

    @MainActor
    func sendPlannedSession(program: Program, day: ProgramDay, maxes: [UserMaxes], using dependencies: PlannerDependencies) async {
        sendStatus = await dependencies.sendPlannedSessionToWatch(program, day, maxes)
    }
}
