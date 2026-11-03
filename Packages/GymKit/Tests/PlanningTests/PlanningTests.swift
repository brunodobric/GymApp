import Catalog
import Foundation
import Models
import SwiftData
import Testing
import Training
@testable import Planning

private let squat = ExerciseRef(catalogId: "squat", name: "Čučanj")
private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")
private let curl = ExerciseRef(catalogId: "curl", name: "Pregib")
/// Petak 15. 1. 2027., 08:00 UTC.
private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private func template(_ name: String, in context: ModelContext, exercises: [ExerciseRef] = [squat]) throws -> WorkoutTemplate {
    let engine = TemplateEngine(context: context)
    let result = try engine.createTemplate(name: name)
    for ref in exercises { try engine.addExercise(ref, inputType: .weightReps, to: result) }
    return result
}

/// Odradi i završi trening iz predloška (jedna serija) i javi to rasporedu.
@discardableResult
private func doWorkout(_ planned: PlannedWorkout, in context: ModelContext, at date: Date) throws -> Session {
    let session = try TemplateStarter(context: context).start(planned, now: date)
    try finish(session, in: context, at: date)
    try ScheduleEngine(context: context).sessionFinished(session)
    return session
}

private func finish(_ session: Session, in context: ModelContext, at date: Date) throws {
    let engine = WorkoutEngine(context: context)
    let set = try #require(session.orderedExercises.first?.orderedSets.first)
    set.weightKg = 50
    set.reps = 5
    try engine.completeSet(set, defaultRestSeconds: 60, now: date)
    try engine.finishSession(session, now: date.addingTimeInterval(1800))
}

/// Raspored A, odmor, B, C.
private func abcSchedule(in context: ModelContext, cycles: Int?) throws -> (Schedule, [WorkoutTemplate]) {
    let engine = ScheduleEngine(context: context)
    let templates = try ["A", "B", "C"].map { try template($0, in: context) }
    let schedule = try engine.createSchedule(name: "ABC", cycleCount: cycles)
    try engine.addWorkout(templates[0], to: schedule)
    try engine.addRestDay(to: schedule)
    try engine.addWorkout(templates[1], to: schedule)
    try engine.addWorkout(templates[2], to: schedule)
    return (schedule, templates)
}

@Suite("Uređivač predložaka")
struct TemplateEngineTests {

    @Test("Nova vježba dobiva tri radne serije, a redoslijed se može mijenjati")
    func addAndMove() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let result = try template("Push", in: context, exercises: [squat, bench, row])
        #expect(result.orderedExercises.map(\.exerciseName) == ["Čučanj", "Potisak s klupe", "Veslanje"])
        #expect(result.orderedExercises[0].orderedSets.count == TemplateEngine.defaultSetCount)
        try engine.moveExercises(in: result, from: IndexSet(integer: 2), to: 0)
        #expect(result.orderedExercises.map(\.exerciseName) == ["Veslanje", "Čučanj", "Potisak s klupe"])
    }

    @Test("Superset mora imati dvije vježbe, a jedna preostala se oslobađa")
    func superset() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let result = try template("T", in: context, exercises: [squat, bench, row])
        let list = result.orderedExercises
        #expect(throws: PlanningError.needsTwoExercises) { try engine.makeSuperset([list[0]], in: result) }
        try engine.makeSuperset([list[0], list[2]], in: result)
        #expect(result.orderedExercises.map(\.exerciseName) == ["Čučanj", "Veslanje", "Potisak s klupe"])
        #expect(list[0].supersetGroupId != nil && list[0].supersetGroupId == list[2].supersetGroupId)
        try engine.removeFromSuperset(list[0])
        #expect(list[0].supersetGroupId == nil && list[2].supersetGroupId == nil)
    }

    @Test("Uklanjanje vježbe popravlja redoslijed i raspušta superset od jedne vježbe")
    func removeExercise() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let result = try template("T", in: context, exercises: [squat, bench, row])
        let list = result.orderedExercises
        try engine.makeSuperset([list[0], list[1]], in: result)
        try engine.removeExercise(list[0])
        #expect(result.orderedExercises.map(\.orderIndex) == [0, 1])
        #expect(result.orderedExercises.allSatisfy { $0.supersetGroupId == nil })
    }

    @Test("Nova serija preuzima ciljeve prethodne, a brisanje popravlja redoslijed")
    func sets() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let exercise = try #require(try template("T", in: context).orderedExercises.first)
        try engine.setTargets(exercise.orderedSets[2], weightKg: 80, reps: 5)
        let added = try engine.addSet(to: exercise)
        #expect(added.targetWeightKg == 80 && added.targetReps == 5)
        try engine.removeSet(exercise.orderedSets[0])
        #expect(exercise.orderedSets.map(\.orderIndex) == [0, 1, 2])
    }

    @Test("Kopija je neovisna o originalu")
    func duplicate() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let original = try template("T", in: context, exercises: [squat, bench])
        let list = original.orderedExercises
        try engine.makeSuperset(list, in: original)
        let copy = try engine.duplicate(original, name: "T 2")
        #expect(copy.orderedExercises.count == 2)
        let copyGroup = copy.orderedExercises[0].supersetGroupId
        #expect(copyGroup != nil && copyGroup != list[0].supersetGroupId)
        try engine.removeExercise(copy.orderedExercises[0])
        #expect(original.orderedExercises.count == 2)
    }
}

@Suite("Pokretanje iz predloška")
struct TemplateStarterTests {

    @Test("Trening preuzima vježbe, ciljeve, pauze i superset, a brisanje predloška ne dira povijest")
    func copiesData() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let result = try template("Push", in: context, exercises: [bench, row, curl])
        let list = result.orderedExercises
        try engine.setTargets(list[0].orderedSets[0], weightKg: 60, reps: 8)
        try engine.removeSet(list[0].orderedSets[2])
        try engine.setRest(120, for: list[0])
        try engine.makeSuperset([list[1], list[2]], in: result)

        let session = try TemplateStarter(context: context).start(result, now: base)
        #expect(session.name == "Push")
        #expect(session.templateId == result.id)
        let exercises = session.orderedExercises
        #expect(exercises.map(\.exerciseName) == ["Potisak s klupe", "Veslanje", "Pregib"])
        #expect(exercises[0].orderedSets.count == 2)
        #expect(exercises[0].orderedSets[0].weightKg == 60 && exercises[0].orderedSets[0].reps == 8)
        #expect(exercises[0].restSeconds == 120)
        #expect(exercises[1].supersetGroupId != nil && exercises[1].supersetGroupId == exercises[2].supersetGroupId)

        try engine.delete(result)
        #expect(session.orderedExercises.count == 3)
    }

    @Test("Ne može se pokrenuti drugi trening dok je jedan aktivan")
    func onlyOneActive() throws {
        let context = try makeContext()
        let result = try template("A", in: context)
        let starter = TemplateStarter(context: context)
        try starter.start(result, now: base)
        #expect(throws: WorkoutError.alreadyActive) { try starter.start(result, now: base) }
    }
}

@Suite("Napredovanje rasporeda")
struct ScheduleProgressTests {

    @Test("Rest dani se prelaze, a ciklus završava nakon zadnjeg treninga")
    func cycles() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)

        var next = try #require(try engine.nextWorkout(of: schedule))
        #expect(next.template.name == "A" && next.cycle == 1)
        try doWorkout(next, in: context, at: base)
        next = try #require(try engine.nextWorkout(of: schedule))
        #expect(next.template.name == "B")
        try doWorkout(next, in: context, at: base.addingTimeInterval(day))
        next = try #require(try engine.nextWorkout(of: schedule))
        #expect(next.template.name == "C")
        try doWorkout(next, in: context, at: base.addingTimeInterval(2 * day))

        next = try #require(try engine.nextWorkout(of: schedule))
        #expect(next.template.name == "A" && next.cycle == 2)
        #expect(schedule.isActive && schedule.currentPosition == 0)
    }

    @Test("Nakon zadnjeg ciklusa raspored postaje neaktivan")
    func endsAfterLastCycle() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: 1)
        for offset in 0..<3 {
            let next = try #require(try engine.nextWorkout(of: schedule))
            try doWorkout(next, in: context, at: base.addingTimeInterval(Double(offset) * day))
        }
        #expect(!schedule.isActive)
        #expect(try engine.nextWorkout(of: schedule) == nil)
        #expect(try engine.upcomingWorkouts().isEmpty)
        #expect(schedule.currentCycle == 1)
    }

    @Test("Propušteni dani ništa ne pomiču")
    func missedDays() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        let first = try #require(try engine.nextWorkout(of: schedule))
        try doWorkout(first, in: context, at: base)
        // Tri tjedna bez treninga: sljedeći je i dalje B, u istom ciklusu.
        let next = try #require(try engine.nextWorkout(of: schedule))
        #expect(next.template.name == "B" && next.cycle == 1)
        try doWorkout(next, in: context, at: base.addingTimeInterval(21 * day))
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")
    }

    @Test("Trening koji nije sljedeći u nizu ne pomiče raspored")
    func unrelatedWorkout() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        let session = try TemplateStarter(context: context).start(templates[2], now: base)
        session.scheduleId = schedule.id
        try finish(session, in: context, at: base)
        #expect(try engine.sessionFinished(session) == false)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
    }

    @Test("Preskakanje trenutnog treninga i poništavanje")
    func skipAndUnskip() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        let first = try #require(try engine.nextWorkout(of: schedule))
        try doWorkout(first, in: context, at: base)

        let skip = try #require(try engine.skipNextWorkout(of: schedule))
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")
        try engine.unskip(skip, in: schedule)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")
    }

    @Test("Preskakanje svih preostalih treninga otvara sljedeći ciklus")
    func skipEverything() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        for _ in 0..<3 { try engine.skipNextWorkout(of: schedule) }
        let next = try #require(try engine.nextWorkout(of: schedule))
        #expect(next.cycle == 2 && next.template.name == "A")
    }

    @Test("Obrisan predložak se prelazi")
    func deletedTemplate() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        try TemplateEngine(context: context).delete(templates[1])
        let first = try #require(try engine.nextWorkout(of: schedule))
        try doWorkout(first, in: context, at: base)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")
    }

    @Test("Raspored kojem su svi predlošci obrisani ne vrti cikluse u nedogled")
    func allTemplatesDeleted() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        for item in templates { try TemplateEngine(context: context).delete(item) }
        try engine.restart(schedule)
        #expect(try engine.nextWorkout(of: schedule) == nil)
        #expect(schedule.currentCycle == 1)
    }

    @Test("Sljedeći trening svakog aktivnog rasporeda")
    func upcoming() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (first, _) = try abcSchedule(in: context, cycles: nil)
        let (second, _) = try abcSchedule(in: context, cycles: nil)
        try engine.setActive(false, for: second)
        #expect(try engine.upcomingWorkouts().count == 1)
        #expect(try engine.upcomingWorkouts().first?.schedule.id == first.id)
    }
}

@Suite("Privremene izmjene ciklusa")
struct CycleOverrideTests {

    private struct Fixture {
        let context: ModelContext
        let engine: ScheduleEngine
        let schedule: Schedule
        let push: WorkoutTemplate
    }

    private func setup() throws -> Fixture {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let push = try template("Push", in: context, exercises: [bench, row, curl])
        let schedule = try engine.createSchedule(name: "Raspored")
        try engine.addWorkout(push, to: schedule)
        return Fixture(context: context, engine: engine, schedule: schedule, push: push)
    }

    @Test("Izbacivanje i zamjena vježbe vrijede samo za taj ciklus i mogu se poništiti")
    func removeAndReplace() throws {
        let fixture = try setup()
        let engine = fixture.engine, schedule = fixture.schedule, push = fixture.push
        let planned = try #require(try engine.nextWorkout(of: schedule))
        let list = push.orderedExercises
        let removal = try engine.removeExercise(list[0], from: planned)
        try engine.replaceExercise(list[1], with: squat, inputType: .weightReps, in: planned)

        let changed = try #require(try engine.nextWorkout(of: schedule))
        #expect(changed.exercises.map(\.ref.name) == ["Čučanj", "Pregib"])
        #expect(changed.exercises[0].isReplacement)
        // Predložak ostaje netaknut.
        #expect(push.orderedExercises.count == 3)

        try engine.undo(removal)
        let restored = try #require(try engine.nextWorkout(of: schedule))
        #expect(restored.exercises.map(\.ref.name) == ["Potisak s klupe", "Čučanj", "Pregib"])
    }

    @Test("Druga izmjena iste vježbe zamjenjuje prvu")
    func replacesPreviousOverride() throws {
        let fixture = try setup()
        let engine = fixture.engine, schedule = fixture.schedule, push = fixture.push
        let planned = try #require(try engine.nextWorkout(of: schedule))
        let target = push.orderedExercises[0]
        try engine.removeExercise(target, from: planned)
        try engine.replaceExercise(target, with: squat, inputType: .weightReps, in: planned)
        let result = try #require(try engine.nextWorkout(of: schedule))
        #expect(result.exercises.map(\.ref.name) == ["Čučanj", "Veslanje", "Pregib"])
    }

    @Test("Trening pokrenut nakon izmjena ne sadrži izbačenu vježbu, a sljedeći ciklus je netaknut")
    func nextCycleUntouched() throws {
        let fixture = try setup()
        let context = fixture.context, engine = fixture.engine, schedule = fixture.schedule, push = fixture.push
        let planned = try #require(try engine.nextWorkout(of: schedule))
        try engine.removeExercise(push.orderedExercises[0], from: planned)

        let session = try TemplateStarter(context: context).start(try #require(try engine.nextWorkout(of: schedule)), now: base)
        #expect(session.orderedExercises.map(\.exerciseName) == ["Veslanje", "Pregib"])
        try finish(session, in: context, at: base)
        try engine.sessionFinished(session)

        let second = try #require(try engine.nextWorkout(of: schedule))
        #expect(second.cycle == 2)
        #expect(second.exercises.count == 3)
    }
}

@Suite("Podsjetnici")
struct ReminderTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let evening = 18 * 60

    @Test("Fiksni dani: odabrani dani u idućih 14 dana, u zadano vrijeme")
    func fixedDays() {
        let dates = ReminderPlanner.fixedDates(
            weekdays: [2, 4, 6], minutesOfDay: evening, now: base, completedDays: [], calendar: calendar
        )
        #expect(dates.count == 6)
        #expect(dates.first == calendar.startOfDay(for: base).addingTimeInterval(18 * 3600))
        #expect(dates.allSatisfy { [2, 4, 6].contains(calendar.component(.weekday, from: $0)) })
    }

    @Test("Fiksni dani: dan s već odrađenim treningom se preskače, a prošlo vrijeme ne")
    func fixedDaysSkipsDone() {
        let today = calendar.startOfDay(for: base)
        let dates = ReminderPlanner.fixedDates(
            weekdays: [6], minutesOfDay: evening, now: base, completedDays: [today], calendar: calendar
        )
        #expect(dates == [today.addingTimeInterval(7 * day + 18 * 3600)])
        let late = ReminderPlanner.fixedDates(
            weekdays: [6], minutesOfDay: evening, now: base.addingTimeInterval(11 * 3600), completedDays: [], calendar: calendar
        )
        #expect(late.first == today.addingTimeInterval(7 * day + 18 * 3600))
    }

    @Test("Fleksibilno: razmak od zadnjeg treninga, rest dani ga produljuju")
    func flexible() {
        let last = base.addingTimeInterval(12 * 3600)
        let today = calendar.startOfDay(for: base)
        #expect(ReminderPlanner.flexibleDate(
            lastWorkoutAt: last, gapDays: 1, restDaysBeforeNext: 0, minutesOfDay: evening, now: base, calendar: calendar
        ) == today.addingTimeInterval(day + 18 * 3600))
        #expect(ReminderPlanner.flexibleDate(
            lastWorkoutAt: last, gapDays: 1, restDaysBeforeNext: 1, minutesOfDay: evening, now: base, calendar: calendar
        ) == today.addingTimeInterval(2 * day + 18 * 3600))
    }

    @Test("Fleksibilno: bez treninga ili uz prošao termin stiže sljedeće zadano vrijeme")
    func flexibleOverdue() {
        let today = calendar.startOfDay(for: base)
        #expect(ReminderPlanner.flexibleDate(
            lastWorkoutAt: nil, gapDays: 1, restDaysBeforeNext: 0, minutesOfDay: evening, now: base, calendar: calendar
        ) == today.addingTimeInterval(18 * 3600))
        #expect(ReminderPlanner.flexibleDate(
            lastWorkoutAt: base.addingTimeInterval(-5 * day), gapDays: 1, restDaysBeforeNext: 0,
            minutesOfDay: evening, now: base.addingTimeInterval(11 * 3600), calendar: calendar
        ) == today.addingTimeInterval(day + 18 * 3600))
    }

    @Test("Zakazivanje iz baze: oba načina, bez podsjetnika tijekom aktivnog treninga")
    func builder() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (flexible, _) = try abcSchedule(in: context, cycles: nil)
        flexible.reminderMinutes = evening
        flexible.reminderMode = .flexible
        let (fixed, _) = try abcSchedule(in: context, cycles: nil)
        fixed.reminderMinutes = evening
        fixed.reminderMode = .fixedDays
        fixed.weekdays = [6]
        let (silent, _) = try abcSchedule(in: context, cycles: nil)
        silent.reminderMinutes = nil

        let builder = ReminderBuilder(context: context)
        let reminders = try builder.reminders(now: base, calendar: calendar)
        #expect(reminders.filter { $0.scheduleId == flexible.id }.count == 1)
        #expect(reminders.filter { $0.scheduleId == fixed.id }.count == 2)
        #expect(!reminders.contains { $0.scheduleId == silent.id })
        #expect(reminders.allSatisfy { $0.workoutName == "A" })

        // Odrađen trening iz fiksnog rasporeda: današnji petak otpada.
        try doWorkout(try #require(try engine.nextWorkout(of: fixed)), in: context, at: base)
        let afterWorkout = try builder.reminders(now: base.addingTimeInterval(3600), calendar: calendar)
        #expect(afterWorkout.filter { $0.scheduleId == fixed.id }.count == 1)
        let flexibleNext = try #require(afterWorkout.first { $0.scheduleId == flexible.id })
        #expect(flexibleNext.fireDate > base)

        // Tijekom aktivnog treninga nema podsjetnika.
        try TemplateStarter(context: context).start(try #require(try engine.nextWorkout(of: flexible)), now: base.addingTimeInterval(7200))
        #expect(try builder.reminders(now: base.addingTimeInterval(7300), calendar: calendar).isEmpty)
    }
}

@Suite("Gotovi programi")
struct ProgramTests {

    private static func loadCatalog() throws -> ExerciseCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Catalog/catalog.json")
        return try ExerciseCatalog(data: Data(contentsOf: url))
    }

    @Test("Svaka vježba programa postoji u katalogu s istom vrstom unosa")
    func exercisesExist() throws {
        let catalog = try Self.loadCatalog()
        for program in ProgramLibrary.all {
            for workout in program.workouts {
                for exercise in workout.exercises {
                    let found = catalog.exercise(withID: exercise.catalogId)
                    #expect(found != nil, "\(program.id): nema \(exercise.catalogId)")
                    #expect(found?.inputType == exercise.inputType, "\(exercise.catalogId): druga vrsta unosa")
                }
            }
        }
    }

    @Test("Nizovi programa pozivaju samo postojeće treninge i imaju zadan broj treninga")
    func sequences() {
        #expect(ProgramLibrary.all.map(\.id).count == Set(ProgramLibrary.all.map(\.id)).count)
        for program in ProgramLibrary.all {
            let keys = Set(program.workouts.map(\.key))
            var workoutDays = 0
            for case .workout(let key) in program.sequence {
                #expect(keys.contains(key), "\(program.id): nepoznat trening \(key)")
                workoutDays += 1
            }
            #expect(workoutDays == program.daysPerWeek, "\(program.id): broj dana")
        }
    }

    @Test("Instalacija stvara predloške i raspored u istom redoslijedu")
    func install() throws {
        let context = try makeContext()
        let program = try #require(ProgramLibrary.all.first { $0.id == "ppl-6" })
        let schedule = try ProgramInstaller(context: context).install(program) { "Vježba \($0)" }
        #expect(schedule.name == program.name && schedule.isActive)
        #expect(schedule.orderedItems.count == 7)
        #expect(schedule.orderedItems.last?.kind == .restDay)
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(templates.count == 3)
        // Ponovljeni treninga u nizu upućuju na isti predložak.
        let ids = schedule.orderedItems.compactMap(\.workoutTemplateId)
        #expect(ids.count == 6 && Set(ids).count == 3)

        let push = try #require(templates.first { $0.name == "Push" })
        #expect(push.orderedExercises.count == 5)
        #expect(push.orderedExercises[0].orderedSets.count == 4)
        #expect(push.orderedExercises[0].orderedSets.allSatisfy { $0.targetReps == 6 })
        #expect(push.orderedExercises[0].exerciseName == "Vježba Barbell_Bench_Press_-_Medium_Grip")
    }

    @Test("Plank ima serije bez ponavljanja")
    func durationExercise() throws {
        let context = try makeContext()
        let program = try #require(ProgramLibrary.all.first { $0.id == "full-body-3" })
        try ProgramInstaller(context: context).install(program) { $0 }
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let plank = try #require(templates.flatMap(\.orderedExercises).first { $0.exerciseName == "Plank" })
        #expect(plank.inputType == .duration)
        #expect(plank.orderedSets.allSatisfy { $0.targetReps == nil })
    }
}

@Suite("Slaganje na iPadu: više stavki odjednom")
struct BulkEditingTests {

    @Test("Više vježbi odjednom ide na kraj ili na zadano mjesto, redom odabira i sa serijama")
    func addSeveralExercises() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let result = try template("T", in: context, exercises: [squat, bench])

        let appended = try engine.addExercises(
            [ExerciseChoice(ref: row, inputType: .weightReps), ExerciseChoice(ref: curl, inputType: .weightReps)],
            to: result
        )
        #expect(appended.count == 2)
        #expect(result.orderedExercises.map(\.exerciseName) == ["Čučanj", "Potisak s klupe", "Veslanje", "Pregib"])
        #expect(appended.allSatisfy { $0.orderedSets.count == TemplateEngine.defaultSetCount })

        let pull = ExerciseRef(catalogId: "pullup", name: "Zgib")
        try engine.addExercises([ExerciseChoice(ref: pull, inputType: .bodyweight)], to: result, at: 1)
        #expect(result.orderedExercises.map(\.exerciseName) == ["Čučanj", "Zgib", "Potisak s klupe", "Veslanje", "Pregib"])
        #expect(result.orderedExercises.map(\.orderIndex) == [0, 1, 2, 3, 4])
        #expect(result.orderedExercises[1].inputType == .bodyweight)

        // Mjesto izvan raspona ide na kraj, a prazan odabir ništa ne mijenja.
        try engine.addExercises([ExerciseChoice(ref: pull, inputType: .bodyweight)], to: result, at: 99)
        #expect(result.orderedExercises.last?.exerciseName == "Zgib")
        #expect(try engine.addExercises([], to: result).isEmpty)
        #expect(result.orderedExercises.count == 6)
    }

    @Test("Umetnuti treninzi ne pomiču sljedeći trening rasporeda")
    func insertWorkouts() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        let names = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.name) })
        func sequence() -> [String] {
            schedule.orderedItems.map { $0.kind == .restDay ? "-" : (names[$0.workoutTemplateId ?? UUID()] ?? "?") }
        }

        // Odradi A: sljedeći je B (pozicija 2).
        let first = try #require(try engine.nextWorkout(of: schedule))
        try doWorkout(first, in: context, at: base)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")

        let added = try engine.insertWorkouts([templates[2], templates[0]], into: schedule, at: 1)
        #expect(added.count == 2)
        #expect(sequence() == ["A", "C", "A", "-", "B", "C"])
        #expect(schedule.orderedItems.map(\.orderIndex) == [0, 1, 2, 3, 4, 5])
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")

        try engine.insertWorkouts([templates[1]], into: schedule)
        #expect(sequence() == ["A", "C", "A", "-", "B", "C", "B"])
    }
}
