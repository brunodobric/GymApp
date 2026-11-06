#if DEBUG
import Foundation
import Models
import Planning
import Stats
import SwiftData
import Testing
@testable import Demo

@Suite("Demo podaci za snimke zaslona")
struct DemoDataTests {
    /// Četvrtak 4. 11. 2027., 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_825_329_600)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func populated(weeks: Int = 10) throws -> (ModelContext, Int) {
        let context = ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
        let count = try DemoDataGenerator(context: context).populate(
            weeks: weeks, scheduleName: "Upper/Lower", exerciseName: { "Vježba \($0)" }, now: now, calendar: calendar
        )
        return (context, count)
    }

    @Test("Četiri treninga tjedno, svi završeni i prije danas")
    func sessions() throws {
        let (context, count) = try populated()
        #expect(count == 40)
        let sessions = try context.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 40)
        #expect(sessions.allSatisfy { $0.state == .finished && $0.endedAt != nil })
        #expect(sessions.allSatisfy { $0.startedAt < calendar.startOfDay(for: now) })
        #expect(try GymQueries(context: context).activeSession() == nil)
    }

    @Test("Raspored napreduje i nudi sljedeći trening")
    func scheduleAdvances() throws {
        let (context, _) = try populated()
        let upcoming = try ScheduleEngine(context: context).upcomingWorkouts()
        #expect(upcoming.count == 1)
        #expect(upcoming.first?.schedule.name == "Upper/Lower")
    }

    @Test("Postavke bez onboardinga, obavijesti i Zdravlja")
    func settings() throws {
        let (context, _) = try populated()
        let settings = try GymQueries(context: context).settings()
        #expect(settings.onboardingCompleted)
        #expect(!settings.notificationsEnabled)
        #expect(!settings.wantsHealthKit)
    }

    @Test("Napredak daje rekorde, a mjere tijela imaju povijest")
    func recordsAndMeasurements() throws {
        let (context, _) = try populated()
        #expect(try !StatisticsEngine(context: context).personalRecords().isEmpty)
        let weights = try context.fetch(FetchDescriptor<BodyMeasurement>()).filter { $0.kind == .weight }
        #expect(weights.count == 10)
        let bench = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.exerciseCatalogId == "barbell-bench-press" }
            .sorted { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
        let firstWeight = bench.first?.orderedSets.first?.weightKg ?? 0
        let lastWeight = bench.last?.orderedSets.first?.weightKg ?? 0
        #expect(firstWeight == 70 && lastWeight > firstWeight)
    }
}
#endif
