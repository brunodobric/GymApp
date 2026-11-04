import Catalog
import Foundation
import Models
import SwiftData
import Testing
import Training
@testable import Planning

/// Petak 15. 1. 2027., 08:00 UTC.
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let oneDay: TimeInterval = 86_400
private let eveningMinutes = 18 * 60

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

/// Raspored: kardio (5 km), snaga, kardio (intervali). Fleksibilni podsjetnik u 18:00.
private struct MixedSchedule {
    let schedule: Schedule
    let run: WorkoutTemplate
    let strength: WorkoutTemplate
    let intervals: WorkoutTemplate
}

private func mixedSchedule(in context: ModelContext) throws -> MixedSchedule {
    let templates = TemplateEngine(context: context)
    let run = try templates.createCardioTemplate(name: "Trčanje 5 km", plan: CardioPreset.run5k.plan)
    let strength = try templates.createTemplate(name: "Noge")
    try templates.addExercise(ExerciseRef(catalogId: "squat", name: "Čučanj"), inputType: .weightReps, to: strength)
    let intervals = try templates.createCardioTemplate(name: "Intervali", plan: CardioPreset.minuteIntervals.plan)
    let engine = ScheduleEngine(context: context)
    let schedule = try engine.createSchedule(name: "Proljeće")
    try engine.addWorkout(run, to: schedule)
    try engine.addWorkout(strength, to: schedule)
    try engine.addWorkout(intervals, to: schedule)
    schedule.reminderMinutes = eveningMinutes
    schedule.reminderMode = .flexible
    try context.save()
    return MixedSchedule(schedule: schedule, run: run, strength: strength, intervals: intervals)
}

@discardableResult
private func importedRun(in context: ModelContext, at date: Date, planId: UUID?) throws -> HealthWorkout {
    let workout = HealthWorkout(
        healthKitWorkoutId: UUID(), name: "Trčanje", startedAt: date, endedAt: date.addingTimeInterval(1_800)
    )
    workout.workoutPlanId = planId
    context.insert(workout)
    try context.save()
    return workout
}

@Suite("Kardio plan")
struct CardioPlanTests {

    @Test("Plan se sprema u predložak i čita natrag")
    func roundTrip() throws {
        let context = try makeContext()
        let plan = CardioPreset.trackIntervals.plan
        let template = try TemplateEngine(context: context).createCardioTemplate(name: "Staza", plan: plan)
        #expect(template.kind == .cardio)
        #expect(template.cardioPlan == plan)
        #expect(template.orderedExercises.isEmpty)

        let copy = try TemplateEngine(context: context).duplicate(template, name: "Staza 2")
        #expect(copy.cardioPlan == plan)
    }

    @Test("Isti plan je uvijek isti tekst")
    func stableEncoding() {
        let plan = CardioPreset.run5k.plan
        #expect(plan.encoded == plan.encoded)
        #expect(CardioPlan.decode(plan.encoded) == plan)
        #expect(CardioPlan.decode("nije json") == nil)
        #expect(CardioPlan.decode(nil) == nil)
    }

    @Test("Ispravnost: bez blokova, bez ponavljanja ili s ciljem 0 plan se ne može zakazati")
    func validity() {
        #expect(CardioPreset.allCases.allSatisfy { $0.plan.isValid })
        #expect(!CardioPlan(intervals: []).isValid)
        #expect(!CardioPlan(intervals: [CardioInterval(work: .open, repeats: 0)]).isValid)
        #expect(!CardioPlan(intervals: [CardioInterval(work: .distance(meters: 0))]).isValid)
        #expect(!CardioPlan(warmup: .time(seconds: -1), intervals: [CardioInterval(work: .open)]).isValid)
        #expect(CardioPlan(intervals: [CardioInterval(work: .open)]).isValid)
    }

    @Test("Ukupna udaljenost i vrijeme")
    func totals() {
        let track = CardioPreset.trackIntervals.plan
        #expect(track.totalDistanceMeters == 2_400)
        #expect(track.totalTimeSeconds == 20 * 60 + 6 * 90)
        #expect(CardioPreset.minuteIntervals.plan.totalTimeSeconds == 15 * 60 + 16 * 60)
    }
}

@Suite("Id plana na satu")
struct CardioPlanIDTests {

    @Test("Isti ulaz daje isti id, a svaka promjena drugi")
    func deterministic() {
        let schedule = UUID()
        let item = UUID()
        let raw = CardioPreset.run5k.plan.encoded!
        let id = CardioPlanID.make(scheduleId: schedule, scheduleItemId: item, cycle: 1, planRaw: raw)
        #expect(id == CardioPlanID.make(scheduleId: schedule, scheduleItemId: item, cycle: 1, planRaw: raw))
        #expect(id != CardioPlanID.make(scheduleId: schedule, scheduleItemId: item, cycle: 2, planRaw: raw))
        #expect(id != CardioPlanID.make(scheduleId: schedule, scheduleItemId: UUID(), cycle: 1, planRaw: raw))
        #expect(id != CardioPlanID.make(scheduleId: UUID(), scheduleItemId: item, cycle: 1, planRaw: raw))
        #expect(id != CardioPlanID.make(scheduleId: schedule, scheduleItemId: item, cycle: 1, planRaw: CardioPreset.easyRun.plan.encoded!))
        // Verzija 5 i varijanta RFC 4122.
        #expect(id.uuidString[id.uuidString.index(id.uuidString.startIndex, offsetBy: 14)] == "5")
    }

    @Test("Trening snage i kardio bez ispravnog plana nemaju id")
    func onlyValidCardio() throws {
        let context = try makeContext()
        let schedule = try mixedSchedule(in: context).schedule
        let engine = ScheduleEngine(context: context)
        let first = try #require(try engine.nextWorkout(of: schedule))
        #expect(CardioPlanID.make(for: first) != nil)

        first.template.cardioPlan = CardioPlan(intervals: [])
        #expect(CardioPlanID.make(for: first) == nil)
    }
}

@Suite("Zakazivanje na sat")
struct CardioScheduleSyncTests {
    private let now = start
    private let plan = CardioPreset.run5k.plan

    private func request(_ id: UUID, at date: Date?) -> CardioScheduleRequest {
        CardioScheduleRequest(planId: id, scheduleId: UUID(), templateId: UUID(), name: "Trčanje", plan: plan, date: date)
    }

    @Test("Novi plan se zakazuje za termin podsjetnika")
    func addsNew() {
        let id = UUID()
        let wanted = request(id, at: now.addingTimeInterval(10 * 3600))
        let changes = CardioScheduleSync.changes(requests: [wanted], scheduled: [], now: now, calendar: utc, limit: 15)
        #expect(changes.add == [wanted])
        #expect(changes.remove.isEmpty)
    }

    @Test("Već zakazan plan ostaje, i kad je zakazan ručno ranije od termina")
    func keepsExisting() {
        let id = UUID()
        let date = now.addingTimeInterval(10 * 3600)
        let same = ScheduledCardioPlan(planId: id, date: date, isComplete: false)
        let manual = ScheduledCardioPlan(planId: id, date: now, isComplete: false)
        for scheduled in [[same], [manual]] {
            let changes = CardioScheduleSync.changes(
                requests: [request(id, at: date)], scheduled: scheduled, now: now, calendar: utc, limit: 15
            )
            #expect(changes.isEmpty)
        }
    }

    @Test("Plan kojeg više nema u rasporedu se miče")
    func removesStale() {
        let old = ScheduledCardioPlan(planId: UUID(), date: now.addingTimeInterval(3600), isComplete: false)
        let changes = CardioScheduleSync.changes(requests: [], scheduled: [old], now: now, calendar: utc, limit: 15)
        #expect(changes.remove == [old])
    }

    @Test("Propušteni plan iz prošlog dana premješta se na novi termin")
    func movesMissed() {
        let id = UUID()
        let missed = ScheduledCardioPlan(planId: id, date: now.addingTimeInterval(-oneDay), isComplete: false)
        let wanted = request(id, at: now.addingTimeInterval(10 * 3600))
        let changes = CardioScheduleSync.changes(requests: [wanted], scheduled: [missed], now: now, calendar: utc, limit: 15)
        #expect(changes.remove == [missed])
        #expect(changes.add == [wanted])
    }

    @Test("Kad se termin pomakne ranije, plan se premješta")
    func movesEarlier() {
        let id = UUID()
        let later = ScheduledCardioPlan(planId: id, date: now.addingTimeInterval(2 * oneDay), isComplete: false)
        let wanted = request(id, at: now.addingTimeInterval(10 * 3600))
        let changes = CardioScheduleSync.changes(requests: [wanted], scheduled: [later], now: now, calendar: utc, limit: 15)
        #expect(changes.remove == [later])
        #expect(changes.add == [wanted])
    }

    @Test("Odrađeni plan ostaje dok se trening ne uveze, i ne zakazuje se ponovno")
    func keepsCompleted() {
        let id = UUID()
        let done = ScheduledCardioPlan(planId: id, date: now.addingTimeInterval(-oneDay), isComplete: true)
        let changes = CardioScheduleSync.changes(
            requests: [request(id, at: now.addingTimeInterval(10 * 3600))], scheduled: [done], now: now, calendar: utc, limit: 15
        )
        #expect(changes.isEmpty)
    }

    @Test("Bez podsjetnika se ništa ne zakazuje samo od sebe, a ručno zakazan plan ostaje")
    func manualOnly() {
        let id = UUID()
        let manual = ScheduledCardioPlan(planId: id, date: now, isComplete: false)
        #expect(CardioScheduleSync.changes(requests: [request(id, at: nil)], scheduled: [], now: now, calendar: utc, limit: 15).isEmpty)
        #expect(CardioScheduleSync.changes(requests: [request(id, at: nil)], scheduled: [manual], now: now, calendar: utc, limit: 15).isEmpty)
    }

    @Test("Ograničenje broja planova: prednost imaju raniji termini")
    func respectsLimit() {
        let existing = ScheduledCardioPlan(planId: UUID(), date: now.addingTimeInterval(3600), isComplete: false)
        let late = request(UUID(), at: now.addingTimeInterval(3 * oneDay))
        let early = request(UUID(), at: now.addingTimeInterval(oneDay))
        let changes = CardioScheduleSync.changes(
            requests: [request(existing.planId, at: existing.date), late, early], scheduled: [existing],
            now: now, calendar: utc, limit: 2
        )
        #expect(changes.add == [early])
        #expect(changes.remove.isEmpty)
    }

    @Test("Iz baze: samo sljedeći kardio trening, s prvim terminom podsjetnika")
    func builder() throws {
        let context = try makeContext()
        let mixed = try mixedSchedule(in: context)
        let (schedule, run) = (mixed.schedule, mixed.run)
        let requests = try CardioScheduleBuilder(context: context).requests(now: start, calendar: utc)
        let only = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(only.templateId == run.id)
        #expect(only.scheduleId == schedule.id)
        #expect(only.date == utc.startOfDay(for: start).addingTimeInterval(18 * 3600))

        // Bez podsjetnika plan i dalje postoji, ali bez termina (samo ručno zakazivanje).
        schedule.reminderMinutes = nil
        let manual = try CardioScheduleBuilder(context: context).requests(now: start, calendar: utc)
        #expect(manual.count == 1)
        #expect(manual.first?.date == nil)

        // Neaktivan raspored nema plan.
        try ScheduleEngine(context: context).setActive(false, for: schedule)
        #expect(try CardioScheduleBuilder(context: context).requests(now: start, calendar: utc).isEmpty)
    }

    @Test("Iz baze: trening snage na redu znači da kardio planova nema")
    func strengthNext() throws {
        let context = try makeContext()
        let schedule = try mixedSchedule(in: context).schedule
        schedule.currentPosition = 1
        try context.save()
        #expect(try CardioScheduleBuilder(context: context).requests(now: start, calendar: utc).isEmpty)
    }
}

@Suite("Uvoz kardija i raspored")
struct CardioLinkTests {

    @Test("Trening sa sata po planu povezuje se s rasporedom, a raspored napreduje")
    func linksByPlanId() throws {
        let context = try makeContext()
        let mixed = try mixedSchedule(in: context)
        let (schedule, run, strength) = (mixed.schedule, mixed.run, mixed.strength)
        let engine = ScheduleEngine(context: context)
        let next = try #require(try engine.nextWorkout(of: schedule))
        let planId = try #require(CardioPlanID.make(for: next))
        let session = try importedRun(in: context, at: start, planId: planId)

        #expect(try CardioPlanLinker(context: context).linkImportedSessions(calendar: utc) == 1)
        #expect(session.scheduleId == schedule.id)
        #expect(session.templateId == run.id)
        #expect(session.name == "Trčanje 5 km")
        #expect(try engine.nextWorkout(of: schedule)?.template.id == strength.id)

        // Drugi poziv ništa ne mijenja.
        #expect(try CardioPlanLinker(context: context).linkImportedSessions(calendar: utc) == 0)
    }

    @Test("Trening bez plana i bez odrađenog plana na satu ostaje samo u povijesti")
    func ignoresUnrelated() throws {
        let context = try makeContext()
        let mixed = try mixedSchedule(in: context)
        let (schedule, run) = (mixed.schedule, mixed.run)
        let walk = try importedRun(in: context, at: start, planId: nil)
        let other = try importedRun(in: context, at: start, planId: UUID())

        #expect(try CardioPlanLinker(context: context).linkImportedSessions(calendar: utc) == 0)
        #expect(walk.scheduleId == nil)
        #expect(other.scheduleId == nil)
        #expect(try ScheduleEngine(context: context).nextWorkout(of: schedule)?.template.id == run.id)
    }

    @Test("Kad Zdravlje ne zna plan, povezuje se trening istog dana kao odrađeni plan na satu")
    func linksByCompletedDay() throws {
        let context = try makeContext()
        let mixed = try mixedSchedule(in: context)
        let (schedule, run) = (mixed.schedule, mixed.run)
        let next = try #require(try ScheduleEngine(context: context).nextWorkout(of: schedule))
        let planId = try #require(CardioPlanID.make(for: next))
        let yesterday = try importedRun(in: context, at: start.addingTimeInterval(-oneDay), planId: nil)
        let today = try importedRun(in: context, at: start.addingTimeInterval(3600), planId: nil)
        let done = ScheduledCardioPlan(planId: planId, date: start, isComplete: true)
        let notDone = ScheduledCardioPlan(planId: planId, date: start, isComplete: false)

        #expect(try CardioPlanLinker(context: context).linkImportedSessions(completedPlans: [notDone], calendar: utc) == 0)
        #expect(try CardioPlanLinker(context: context).linkImportedSessions(completedPlans: [done], calendar: utc) == 1)
        #expect(today.templateId == run.id)
        #expect(yesterday.scheduleId == nil)
    }

    @Test("Dva kardio treninga zaredom: oba se povezuju redom")
    func linksConsecutive() throws {
        let context = try makeContext()
        let templates = TemplateEngine(context: context)
        let first = try templates.createCardioTemplate(name: "Lagano", plan: CardioPreset.easyRun.plan)
        let second = try templates.createCardioTemplate(name: "Staza", plan: CardioPreset.trackIntervals.plan)
        let engine = ScheduleEngine(context: context)
        let schedule = try engine.createSchedule(name: "Trčanje", cycleCount: 1)
        try engine.addWorkout(first, to: schedule)
        try engine.addWorkout(second, to: schedule)

        let next = try #require(try engine.nextWorkout(of: schedule))
        let firstId = try #require(CardioPlanID.make(for: next))
        let secondItem = schedule.orderedItems[1]
        let secondId = CardioPlanID.make(
            scheduleId: schedule.id, scheduleItemId: secondItem.id, cycle: 1, planRaw: try #require(second.cardioPlanRaw)
        )
        // Uvoz stiže obrnutim redom: drugi trening se povezuje tek kad raspored dođe do njega.
        try importedRun(in: context, at: start.addingTimeInterval(oneDay), planId: secondId)
        try importedRun(in: context, at: start, planId: firstId)

        #expect(try CardioPlanLinker(context: context).linkImportedSessions(calendar: utc) == 2)
        #expect(!schedule.isActive)
    }
}

@Suite("Podsjetnici za kardio")
struct CardioReminderTests {

    @Test("Podsjetnik zna da je trening kardio i na koju stavku upućuje")
    func reminderCarriesPlan() throws {
        let context = try makeContext()
        let mixed = try mixedSchedule(in: context)
        let (schedule, run) = (mixed.schedule, mixed.run)
        let reminder = try #require(try ReminderBuilder(context: context).reminders(now: start, calendar: utc).first)
        #expect(reminder.isCardio)
        #expect(reminder.templateId == run.id)
        #expect(reminder.scheduleItemId == schedule.orderedItems.first?.id)
        #expect(reminder.cycle == 1)
    }

    @Test("Tijekom aktivnog treninga nema obavijesti, ali termin za plan na satu postoji")
    func activeSession() throws {
        let context = try makeContext()
        _ = try mixedSchedule(in: context)
        _ = try WorkoutEngine(context: context).startSession(name: "Prazan", now: start)
        #expect(try ReminderBuilder(context: context).reminders(now: start, calendar: utc).isEmpty)
        #expect(try ReminderBuilder(context: context).plannedReminders(now: start, calendar: utc).count == 1)
        #expect(try CardioScheduleBuilder(context: context).requests(now: start, calendar: utc).first?.date != nil)
    }
}
