import Foundation
import Testing
import Units
@testable import WidgetData

/// Petak 15. 1. 2027., 08:00 UTC.
private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: base)!.start }

@Suite("Snimka za widgete")
struct WidgetSnapshotTests {
    private let croatian = Locale(identifier: "hr_HR")

    @Test("Plan vježbe: serije × ponavljanja i težina, trajanje ili samo serije")
    func plannedSummary() {
        let unit = WeightUnit.kilograms
        #expect(WidgetSnapshot.PlannedExercise(name: "Bench", workingSets: 4, reps: 8, weightKg: 80)
            .summary(unit: unit, locale: croatian) == "4 × 8 · 80 kg")
        #expect(WidgetSnapshot.PlannedExercise(name: "Dips", workingSets: 3, reps: 12)
            .summary(unit: unit, locale: croatian) == "3 × 12")
        #expect(WidgetSnapshot.PlannedExercise(name: "Plank", workingSets: 3, durationSeconds: 45)
            .summary(unit: unit, locale: croatian) == "3 × 0:45")
        #expect(WidgetSnapshot.PlannedExercise(name: "Bench", workingSets: 2, reps: 5, weightKg: 82.5)
            .summary(unit: unit, locale: croatian) == "2 × 5 · 82,5 kg")
        #expect(WidgetSnapshot.PlannedExercise(name: "Prazno", workingSets: 0).summary(unit: unit) == "")
    }

    @Test("Težina se prikazuje u odabranoj jedinici")
    func plannedSummaryPounds() {
        let exercise = WidgetSnapshot.PlannedExercise(name: "Bench", workingSets: 1, reps: 5, weightKg: 45.359237)
        #expect(exercise.summary(unit: .pounds, locale: Locale(identifier: "en_US")) == "1 × 5 · 100 lbs")
    }

    @Test("Sljedeći trening pamti najviše tri vježbe i broji ostale")
    func nextWorkoutLimit() {
        let exercises = (1...5).map { WidgetSnapshot.PlannedExercise(name: "V\($0)", workingSets: 3) }
        let next = WidgetSnapshot.NextWorkout(name: "Push", scheduleName: nil, exerciseCount: 5, exercises: exercises)
        #expect(next.exercises.map(\.name) == ["V1", "V2", "V3"])
        #expect(next.remainingExercises == 2)
    }

    @Test("Krivulja težine je između 0 i 1, ravna je na sredini, a jedna točka nema krivulje")
    func sparkline() {
        let weight = WidgetSnapshot.BodyWeight(latestKg: 80, date: base, changeKg: nil, points: [82, 81, 80])
        #expect(weight.normalizedPoints == [1, 0.5, 0])
        #expect(WidgetSnapshot.BodyWeight(latestKg: 80, date: base, changeKg: nil, points: [80, 80]).normalizedPoints == [0.5, 0.5])
        #expect(WidgetSnapshot.BodyWeight(latestKg: 80, date: base, changeKg: nil, points: [80]).normalizedPoints.isEmpty)
        let many = WidgetSnapshot.BodyWeight(latestKg: 80, date: base, changeKg: nil, points: (1...50).map(Double.init))
        #expect(many.points.count == WidgetSnapshot.BodyWeight.maxPoints)
        #expect(many.points.last == 50)
    }

    @Test("Zadnji trening pamti najviše dva rekorda")
    func lastWorkoutHighlights() {
        let highlights = (1...3).map { WidgetSnapshot.Highlight(exercise: "V\($0)", value: "\($0)") }
        let last = WidgetSnapshot.LastWorkout(name: "Legs", startedAt: base, durationSeconds: 60, mix: .strength, hardSets: 3, highlights: highlights)
        #expect(last.highlights.count == 2)
    }

    @Test("Dani od treninga se broje po kalendarskim danima")
    func daysAgo() {
        #expect(WidgetDates.daysAgo(base, now: base, calendar: calendar) == 0)
        // Jučer u 23:00 je prije jednog dana i kad je prošlo samo nekoliko sati.
        let lateYesterday = calendar.startOfDay(for: base).addingTimeInterval(-3600)
        #expect(WidgetDates.daysAgo(lateYesterday, now: base, calendar: calendar) == 1)
        #expect(WidgetDates.daysAgo(base.addingTimeInterval(-3 * day), now: base, calendar: calendar) == 3)
        #expect(WidgetDates.daysAgo(base.addingTimeInterval(day), now: base, calendar: calendar) == 0)
    }

    @Test("Ponoći za vremensku crtu widgeta")
    func midnights() {
        let midnights = WidgetDates.nextMidnights(after: base, count: 3, calendar: calendar)
        let today = calendar.startOfDay(for: base)
        #expect(midnights == [1, 2, 3].map { today.addingTimeInterval(Double($0) * day) })
    }
}

@Suite("Tjedan u widgetu")
struct WidgetWeekTests {
    private func week(sessions: Int, goal: Int?, streak: Int) -> WidgetSnapshot.Week {
        var week = WidgetSnapshot.Week(start: weekStart, sessions: sessions, goal: goal, streakWeeks: streak, calendar: calendar)
        week.days[0].strength = sessions > 0
        return week
    }

    @Test("U istom tjednu snimka ostaje ista")
    func sameWeek() {
        let current = week(sessions: 2, goal: 3, streak: 1)
        #expect(current.current(at: base, calendar: calendar) == current)
        #expect(current.current(at: weekStart, calendar: calendar) == current)
    }

    @Test("Idući tjedan je prazan, a niz se nastavlja samo ako je cilj ispunjen")
    func nextWeek() {
        let nextMonday = weekStart.addingTimeInterval(7 * day + 3600)
        let met = week(sessions: 3, goal: 3, streak: 4).current(at: nextMonday, calendar: calendar)
        #expect(met.sessions == 0)
        #expect(met.streakWeeks == 4)
        #expect(met.goal == 3)
        #expect(calendar.isDate(met.start, inSameDayAs: weekStart.addingTimeInterval(7 * day)))
        #expect(met.days.count == 7)
        #expect(!met.days.contains(where: \.isTrained))

        let missed = week(sessions: 2, goal: 3, streak: 4).current(at: nextMonday, calendar: calendar)
        #expect(missed.streakWeeks == 0)
    }

    @Test("Nakon praznog tjedna niz je prekinut")
    func twoWeeksLater() {
        let later = week(sessions: 3, goal: 3, streak: 4).current(at: weekStart.addingTimeInterval(15 * day), calendar: calendar)
        #expect(later.streakWeeks == 0)
        #expect(later.sessions == 0)
    }

    @Test("Bez cilja tjedan s jednim treningom nastavlja niz")
    func withoutGoal() {
        let next = week(sessions: 1, goal: nil, streak: 2).current(at: weekStart.addingTimeInterval(8 * day), calendar: calendar)
        #expect(next.streakWeeks == 2)
        #expect(next.goalFraction == nil)
    }

    @Test("Udio cilja je ograničen na 1, a cilj 0 znači bez cilja")
    func fraction() {
        #expect(week(sessions: 2, goal: 4, streak: 0).goalFraction == 0.5)
        #expect(week(sessions: 5, goal: 4, streak: 0).goalFraction == 1)
        #expect(week(sessions: 1, goal: 0, streak: 0).goal == nil)
    }
}

@Suite("Poveznice widgeta")
struct WidgetLinkTests {
    @Test("Svaka poveznica se pročita natrag", arguments: [
        WidgetLink.home, .startWorkout, .activeWorkout, .week, .bodyWeight, .lastWorkout,
    ])
    func roundTrip(_ link: WidgetLink) {
        #expect(WidgetLink(url: link.url) == link)
    }

    @Test("Trening u tijeku ima istu poveznicu kao Live Activity, a tuđe poveznice se odbijaju")
    func foreign() {
        #expect(WidgetLink.activeWorkout.url.absoluteString == "apolon://trening")
        #expect(WidgetLink(url: URL(string: "https://apolon.app/trening")!) == nil)
        #expect(WidgetLink(url: URL(string: "apolon://nepoznato")!) == nil)
    }
}

@Suite("Spremanje snimke")
struct WidgetSnapshotStoreTests {
    @Test("Snimka se sprema i čita, a ista snimka s novim vremenom nije promjena")
    func saveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.load() == nil)

        let snapshot = WidgetSnapshot.sample(now: base, calendar: calendar)
        #expect(try store.save(snapshot))
        #expect(store.load() == snapshot)

        var later = snapshot
        later.generatedAt = base.addingTimeInterval(60)
        #expect(try !store.save(later))

        later.week?.sessions = 3
        #expect(try store.save(later))
        #expect(store.load()?.week?.sessions == 3)
    }

    @Test("Bez App Groupa nema spremanja")
    func withoutDirectory() throws {
        let store = WidgetSnapshotStore(directory: nil)
        #expect(try !store.save(.empty))
        #expect(store.load() == nil)
    }
}
