import Foundation
import Models
import SwiftData
import Testing
@testable import Stats

/// Petak 15. 1. 2027., 08:00 UTC (kao u `StatsTests`).
private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

/// Završen trening bez vježbi, od sat vremena.
private func addSession(_ context: ModelContext, at date: Date) -> Session {
    let session = Session(name: "Trening", startedAt: date)
    session.state = .finished
    session.endedAt = date.addingTimeInterval(3600)
    context.insert(session)
    return session
}

@Suite("Streak")
struct StreakStatusTests {
    private let isCardio: (String) -> Bool = { _ in false }
    /// Ponedjeljak tjedna u kojem je `base` (petak).
    private var monday: Date { base.addingTimeInterval(-4 * day) }

    /// Treninzi u tjednima prije tekućeg: `weeks[0]` je prošli tjedan, svaki trening u ponedjeljak.
    private func history(_ context: ModelContext, weeks: [Int]) throws -> [Session] {
        var sessions: [Session] = []
        for (index, count) in weeks.enumerated() {
            for offset in 0..<count {
                let date = monday.addingTimeInterval(-Double(index + 1) * 7 * day + Double(offset) * day)
                sessions.append(addSession(context, at: date))
            }
        }
        return sessions
    }

    /// Treninzi tekućeg tjedna, od ponedjeljka.
    private func thisWeek(_ context: ModelContext, count: Int) throws -> [Session] {
        (0..<count).map { addSession(context, at: monday.addingTimeInterval(Double($0) * 3600)) }
    }

    @Test("Streak: ispunjen tjedan je osiguran i ulazi u niz")
    func streakSecured() throws {
        let context = try makeContext()
        let sessions = try history(context, weeks: [3, 3]) + thisWeek(context, count: 3)
        let progress = WeekProgress.make(sessions: sessions, now: base, goal: 3, calendar: calendar, isCardio: isCardio)
        #expect(progress.previousStreakWeeks == 2)
        #expect(progress.streakIfWeekEndsNow == 3)
        let status = StreakStatus(progress: progress, now: base, calendar: calendar)
        #expect(status.state == .secured)
        #expect(status.weeks == 3)
        #expect(status.remaining == 0)
        #expect(!status.isLastChance)
    }

    @Test("Streak: tjedan s premalo treninga prekida niz, pa je niz u opasnosti")
    func streakAtRisk() throws {
        let context = try makeContext()
        let sessions = try history(context, weeks: [3, 3]) + thisWeek(context, count: 1)
        let progress = WeekProgress.make(sessions: sessions, now: base, goal: 3, calendar: calendar, isCardio: isCardio)
        #expect(progress.streakIfWeekEndsNow == 0)
        let status = StreakStatus(progress: progress, now: base, calendar: calendar)
        #expect(status.state == .atRisk)
        #expect(status.weeks == 2)
        #expect(status.sessions == 1)
        #expect(status.remaining == 2)
        // Petak: do kraja tjedna su petak, subota i nedjelja.
        #expect(status.daysLeft == 3)
        #expect(!status.isLastChance)

        let sunday = monday.addingTimeInterval(6 * day + 10 * 3600)
        let lastDay = StreakStatus(progress: progress, now: sunday, calendar: calendar)
        #expect(lastDay.daysLeft == 1)
        #expect(lastDay.isLastChance)
    }

    @Test("Streak: tjedan bez treninga može biti pauza, pa niz ostaje i ne prijeti gubitkom")
    func streakCanGrowAfterPause() throws {
        let context = try makeContext()
        let progress = WeekProgress.make(
            sessions: try history(context, weeks: [3, 3]), now: base, goal: 3, calendar: calendar, isCardio: isCardio
        )
        #expect(progress.streakIfWeekEndsNow == 2)
        let status = StreakStatus(progress: progress, now: base, calendar: calendar)
        #expect(status.state == .canGrow)
        #expect(status.remaining == 3)

        // Pauza je bila prošli tjedan: drugi prazan tjedan zaredom prekida niz.
        let afterPause = WeekProgress.make(
            sessions: try history(try makeContext(), weeks: [0, 3, 3]), now: base, goal: 3, calendar: calendar, isCardio: isCardio
        )
        #expect(afterPause.previousStreakWeeks == 2)
        #expect(StreakStatus(progress: afterPause, now: base, calendar: calendar).state == .atRisk)
    }

    @Test("Streak: bez niza ispunjen cilj započinje niz, a bez cilja broji se jedan trening")
    func streakNotStarted() throws {
        let context = try makeContext()
        let sessions = try history(context, weeks: [1]) + thisWeek(context, count: 1)
        let progress = WeekProgress.make(sessions: sessions, now: base, goal: 3, calendar: calendar, isCardio: isCardio)
        let status = StreakStatus(progress: progress, now: base, calendar: calendar)
        #expect(status.state == .notStarted)
        #expect(status.weeks == 0)
        #expect(status.remaining == 2)

        let withoutGoal = WeekProgress.make(sessions: sessions, now: base, goal: nil, calendar: calendar, isCardio: isCardio)
        let free = StreakStatus(progress: withoutGoal, now: base, calendar: calendar)
        #expect(free.state == .secured)
        #expect(free.target == 1)
        #expect(free.weeks == 2)
    }
}
