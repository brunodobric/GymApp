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

    @Test("Ažuriranje treninga preuzima strukturu odrađenog treninga, a ciljevi ostaju")
    func updateFromSession() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let result = try template("Push", in: context, exercises: [bench, row, curl])
        let first = try #require(result.orderedExercises.first)
        try engine.setTargets(try #require(first.orderedSets.first), weightKg: 60, reps: 8)
        first.notes = "Sjedalo 4"
        let session = try TemplateStarter(context: context).start(result, now: base)
        let workout = WorkoutEngine(context: context)
        let done = session.orderedExercises
        try #require(done.count == 3)
        // Potisak: 4 serije umjesto 3, veslanje preskočeno, pregib 2 serije, dodan čučanj.
        try workout.addSet(to: done[0])
        for (exercise, count) in [(done[0], 4), (done[2], 2)] {
            for set in exercise.orderedSets.prefix(count) {
                set.weightKg = set.weightKg ?? 20
                set.reps = set.reps ?? 10
                try workout.completeSet(set, defaultRestSeconds: 90, now: base)
            }
        }
        let added = try workout.addExercise(squat, inputType: .weightReps, to: session)
        let squatSet = try #require(added.orderedSets.first)
        squatSet.weightKg = 100
        squatSet.reps = 5
        try workout.completeSet(squatSet, defaultRestSeconds: 90, now: base)

        let changes = engine.changes(from: session, to: result)
        #expect(changes.added == ["Čučanj"])
        #expect(changes.removed == ["Veslanje"])
        #expect(changes.setCounts == [.init(name: "Potisak s klupe", from: 3, to: 4), .init(name: "Pregib", from: 3, to: 2)])
        #expect(!changes.isEmpty)

        try engine.updateTemplate(result, from: session)
        let updated = result.orderedExercises
        #expect(updated.map(\.exerciseName) == ["Potisak s klupe", "Pregib", "Čučanj"])
        #expect(updated.map(\.orderedSets.count) == [4, 2, 1])
        #expect(updated[0].orderedSets.first?.targetWeightKg == 60)
        #expect(updated[0].notes == "Sjedalo 4")
        #expect(updated[2].orderedSets.first?.targetReps == 5)
        #expect(updated[2].orderedSets.first?.targetWeightKg == nil)
        #expect(engine.changes(from: session, to: result).isEmpty)
    }

    @Test("Raspon iz predloška, prijedlog veće težine i bilješka idu u trening")
    func progression() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let result = try template("Push", in: context, exercises: [bench])
        let exercise = try #require(result.orderedExercises.first)
        exercise.notes = "  Sjedalo 4  "
        for set in exercise.orderedSets {
            try engine.setTargets(set, weightKg: nil, reps: 8)
            set.targetRepsMax = 12
        }

        let first = try TemplateStarter(context: context, weightStep: { _ in 2.5 }).start(result, now: base)
        let started = try #require(first.orderedExercises.first)
        #expect(started.targetRepsMin == 8)
        #expect(started.targetRepsMax == 12)
        #expect(started.notes == "Sjedalo 4")
        #expect(started.loadChangeKg == nil)
        let workout = WorkoutEngine(context: context)
        for set in started.orderedSets {
            set.weightKg = 80
            set.reps = 12
            try workout.completeSet(set, defaultRestSeconds: 90, now: base)
        }
        try workout.finishSession(first, now: base.addingTimeInterval(3600))

        let second = try TemplateStarter(context: context, weightStep: { _ in 2.5 }).start(result, now: base + 86_400)
        let next = try #require(second.orderedExercises.first)
        #expect(next.loadChangeKg == 2.5)
        #expect(next.orderedSets.allSatisfy { $0.weightKg == 82.5 && $0.reps == 8 })

        // Isključen prijedlog veće težine: težina ostaje kao prošli put.
        try workout.discardSession(second)
        try GymQueries(context: context).settings().suggestsHeavierWeight = false
        let third = try TemplateStarter(context: context, weightStep: { _ in 2.5 }).start(result, now: base + 2 * 86_400)
        let plain = try #require(third.orderedExercises.first)
        #expect(plain.loadChangeKg == nil)
        #expect(plain.orderedSets.allSatisfy { $0.weightKg == 80 && $0.reps == 12 })
    }

    @Test("Izbor treninga bez rasporeda: samo treninzi snage s vježbama, po nazivu")
    func startableTemplates() throws {
        let context = try makeContext()
        let pull = try template("Pull", in: context)
        let legs = try template("noge", in: context)
        let push = try template("Push", in: context)
        let empty = try template("Prazan", in: context, exercises: [])
        let cardio = try template("Trčanje", in: context)
        cardio.kind = .cardio

        let result = TemplateStarter.startable([pull, empty, push, cardio, legs])
        #expect(result.map(\.name) == ["noge", "Pull", "Push"])
        #expect(TemplateStarter.startable([]).isEmpty)
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

    @Test("Novi trening iz rasporeda nastaje prazan i ide na kraj niza")
    func addNewWorkout() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let schedule = try engine.createSchedule(name: "Novi")
        try engine.addRestDay(to: schedule)

        let created = try engine.addNewWorkout(named: "Novi trening", to: schedule)

        #expect(created.name == "Novi trening" && created.kind == .strength)
        #expect((created.exercises ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 1)
        let items = schedule.orderedItems
        #expect(items.map(\.kind) == [.restDay, .workout])
        #expect(items.last?.workoutTemplateId == created.id)
    }

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

    @Test("Trening odrađen mimo reda bilježi se kao odrađen, a sljedeći ostaje prvi neodrađeni")
    func unrelatedWorkout() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        let session = try TemplateStarter(context: context).start(templates[2], now: base)
        session.scheduleId = schedule.id
        try finish(session, in: context, at: base)
        #expect(try engine.sessionFinished(session))
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
        try doWorkout(try #require(try engine.nextWorkout(of: schedule)), in: context, at: base)
        // C je već odrađen, pa iza B ciklus završava.
        try doWorkout(try #require(try engine.nextWorkout(of: schedule)), in: context, at: base)
        #expect(schedule.currentCycle == 2)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
    }

    @Test("Trening koji nije u rasporedu ne mijenja raspored")
    func workoutOutsideSchedule() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        let other = try template("D", in: context)
        let session = try TemplateStarter(context: context).start(other, now: base)
        session.scheduleId = schedule.id
        try finish(session, in: context, at: base)
        #expect(try engine.sessionFinished(session) == false)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
    }

    @Test("Trening premješten na početak novog rasporeda postaje sljedeći")
    func movedToFrontBecomesNext() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let templates = try ["A", "B"].map { try template($0, in: context) }
        let schedule = try engine.createSchedule(name: "Novi")
        try engine.addWorkout(templates[0], to: schedule)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
        try engine.addWorkout(templates[1], to: schedule)
        try engine.moveItems(in: schedule, from: IndexSet(integer: 1), to: 0)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")
    }

    @Test("Neodrađeni trening premješten ispred odrađenog je sljedeći, a odrađeni se ne ponavlja")
    func movedBeforeDoneWorkout() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        try doWorkout(try #require(try engine.nextWorkout(of: schedule)), in: context, at: base)
        // A, odmor, B, C -> C, A, odmor, B
        try engine.moveItems(in: schedule, from: IndexSet(integer: 3), to: 0)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")
        try doWorkout(try #require(try engine.nextWorkout(of: schedule)), in: context, at: base)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")
        try doWorkout(try #require(try engine.nextWorkout(of: schedule)), in: context, at: base)
        #expect(schedule.currentCycle == 2)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")
    }

    @Test("Napredak iz starije verzije (samo pozicija) ostaje i nakon premještanja")
    func legacyPositionSurvivesMove() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        // Starija verzija: A odrađen, zapisano samo pozicijom.
        schedule.currentPosition = 1
        try context.save()
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")
        // A, odmor, B, C -> A, odmor, C, B
        try engine.moveItems(in: schedule, from: IndexSet(integer: 3), to: 2)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")
        try engine.moveItems(in: schedule, from: IndexSet(integer: 0), to: 4)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")
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

    @Test("Preskočeni treninzi tekućeg ciklusa imaju naziv i mogu se vratiti")
    func skippedWorkoutsList() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        #expect(try engine.skippedWorkouts(of: schedule).isEmpty)
        try engine.skipNextWorkout(of: schedule)
        let skipped = try engine.skippedWorkouts(of: schedule)
        #expect(skipped.map(\.templateName) == ["A"])
        try engine.unskip(skipped[0].change, in: schedule)
        #expect(try engine.skippedWorkouts(of: schedule).isEmpty)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
    }

    @Test("Ponovno pokretanje briše izmjene starog prolaza")
    func restartClearsOverrides() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: 1)
        try engine.skipNextWorkout(of: schedule)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")
        try engine.restart(schedule)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
        #expect(try context.fetch(FetchDescriptor<CycleOverride>()).isEmpty)
    }

    @Test("Izmjene prošlih ciklusa se brišu kad počne novi ciklus")
    func prunesPastCycles() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        try engine.skipNextWorkout(of: schedule)
        #expect(try context.fetch(FetchDescriptor<CycleOverride>()).count == 1)
        try engine.skipNextWorkout(of: schedule)
        try engine.skipNextWorkout(of: schedule)
        #expect(schedule.currentCycle == 2)
        #expect(try context.fetch(FetchDescriptor<CycleOverride>()).isEmpty)
    }

    @Test("Brisanje rasporeda briše i njegove izmjene, a izmjene drugog rasporeda ostaju")
    func deleteScheduleWithOverrides() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        let other = try engine.createSchedule(name: "Drugi", cycleCount: nil)
        try engine.addWorkout(templates[0], to: other)
        try engine.addWorkout(templates[1], to: other)
        try engine.skipNextWorkout(of: schedule)
        try engine.skipNextWorkout(of: other)
        try engine.delete(schedule)
        let left = try context.fetch(FetchDescriptor<CycleOverride>())
        #expect(left.map(\.scheduleId) == [Optional(other.id)])
        #expect(try context.fetch(FetchDescriptor<Schedule>()).map(\.id) == [other.id])
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

    @Test("Izbor treninga iz rasporeda: svaki trening snage jednom, redom niza, bez neaktivnog rasporeda")
    func workoutChoices() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        // A se ponavlja na kraju, a trening bez vježbi se ne nudi.
        try engine.addWorkout(templates[0], to: schedule)
        try engine.addNewWorkout(named: "Prazan", to: schedule)
        #expect(try engine.workoutChoices(of: schedule).map(\.template.name) == ["A", "B", "C"])

        try engine.setActive(false, for: schedule)
        #expect(try engine.workoutChoices(of: schedule).isEmpty)
    }

    @Test("Ponovljeni trening u izboru je prvi neodrađeni, s izmjenama ciklusa")
    func workoutChoicesUseUpcomingItem() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: nil)
        let repeated = try engine.addWorkout(templates[0], to: schedule)
        let first = try #require(try engine.nextWorkout(of: schedule))
        try doWorkout(first, in: context, at: base)

        let choice = try #require(try engine.workoutChoices(of: schedule).first)
        #expect(choice.item.id == repeated.id)
        try engine.removeExercise(try #require(templates[0].orderedExercises.first), from: choice)
        #expect(try engine.workoutChoices(of: schedule).first?.exercises.isEmpty == true)
    }

    @Test("Odabrani trening mimo reda je odrađen, a sljedeći ostaje prvi neodrađeni")
    func startChosenWorkout() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        let choices = try engine.workoutChoices(of: schedule)
        try doWorkout(choices[2], in: context, at: base)
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "A")
        try doWorkout(choices[0], in: context, at: base.addingTimeInterval(day))
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")
        try doWorkout(choices[1], in: context, at: base.addingTimeInterval(2 * day))
        #expect(schedule.currentCycle == 2)
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

    @Test("Umetnuti treninzi nisu odrađeni, pa je prvi od njih sljedeći")
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
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "C")

        try engine.insertWorkouts([templates[1]], into: schedule)
        #expect(sequence() == ["A", "C", "A", "-", "B", "C", "B"])
    }
}


@Suite("Broj ciklusa")
struct CycleCountRangeTests {
    @Test("Raspon počinje od tekućeg ciklusa i ide do 52")
    func usualRange() {
        #expect(ScheduleEngine.cycleCountRange(currentCycle: 0) == 1...52)
        #expect(ScheduleEngine.cycleCountRange(currentCycle: 1) == 1...52)
        #expect(ScheduleEngine.cycleCountRange(currentCycle: 30) == 30...52)
    }

    @Test("Raspored nakon 52 ciklusa ima neprazan raspon")
    func pastUsualMaximum() {
        #expect(ScheduleEngine.cycleCountRange(currentCycle: 52) == 52...52)
        #expect(ScheduleEngine.cycleCountRange(currentCycle: 60) == 60...60)
    }
}

@Suite("Novi trening iz odrađenog treninga")
struct TemplateFromSessionTests {

    /// Odrađeni trening: potisak (zagrijavanje + dvije radne), superset veslanja i pregiba.
    private func pastSession(in context: ModelContext) throws -> Session {
        let engine = WorkoutEngine(context: context)
        let session = try engine.startSession(name: "Push", now: base)
        let pressing = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        for set in pressing.orderedSets { try engine.removeSet(set, now: base) }
        for (kind, weight, reps) in [(SetKind.warmUp, 40.0, 10), (.working, 80, 8), (.working, 85, 6)] {
            let set = try engine.addSet(to: pressing, kind: kind, now: base)
            set.weightKg = weight
            set.reps = reps
            try engine.completeSet(set, defaultRestSeconds: 0, now: base)
        }
        pressing.restSeconds = 150
        let rowing = try engine.addExercise(row, inputType: .weightReps, to: session, now: base)
        let curling = try engine.addExercise(curl, inputType: .weightReps, to: session, now: base)
        try engine.makeSuperset([rowing, curling], in: session, now: base)
        for exercise in [rowing, curling] {
            let set = exercise.orderedSets[0]
            set.weightKg = 30
            set.reps = 12
            try engine.completeSet(set, defaultRestSeconds: 0, now: base)
        }
        try engine.finishSession(session, now: base.addingTimeInterval(3600))
        return session
    }

    @Test("Predložak ima naziv, vježbe, završene serije kao ciljeve, pauze i superset")
    func copiesSession() throws {
        let context = try makeContext()
        let session = try pastSession(in: context)
        let template = try TemplateEngine(context: context).createTemplate(from: session)

        #expect(template.name == "Push")
        #expect(template.kind == .strength)
        let exercises = template.orderedExercises
        #expect(exercises.map(\.exerciseName) == ["Potisak s klupe", "Veslanje", "Pregib"])
        #expect(exercises[0].orderedSets.map(\.kind) == [.warmUp, .working, .working])
        #expect(exercises[0].orderedSets.map(\.targetWeightKg) == [40, 80, 85])
        #expect(exercises[0].orderedSets.map(\.targetReps) == [10, 8, 6])
        #expect(exercises[0].restSeconds == 150)
        // Nezavršene serije iz treninga su obrisane pri završetku, pa ostaje jedna serija.
        #expect(exercises[1].orderedSets.count == 1)
        let group = exercises[1].supersetGroupId
        #expect(group != nil && group == exercises[2].supersetGroupId)
        #expect(group != session.orderedExercises[1].supersetGroupId)
    }

    @Test("Izmjene novog treninga ne diraju odrađeni trening")
    func independentCopy() throws {
        let context = try makeContext()
        let session = try pastSession(in: context)
        let engine = TemplateEngine(context: context)
        let template = try engine.createTemplate(from: session)
        template.name = "Push 2"
        try engine.removeExercise(template.orderedExercises[0])
        try engine.removeExercise(template.orderedExercises[0])
        #expect(template.orderedExercises.count == 1)
        // Superset s jednom vježbom se raspušta.
        #expect(template.orderedExercises[0].supersetGroupId == nil)
        #expect(session.name == "Push")
        #expect(session.orderedExercises.count == 3)
        #expect(session.orderedExercises[0].orderedSets.count == 3)
    }
}

@Suite("Izlazak iz uređivača bez spremanja")
struct EditSnapshotTests {
    @Test("Odbačeni novi trening iz rasporeda nestaje iz niza i iz treninga")
    func discardNewWorkout() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, _) = try abcSchedule(in: context, cycles: nil)
        let created = try engine.addNewWorkout(named: "Novi", to: schedule)
        #expect(schedule.orderedItems.count == 5)
        try engine.discardNewWorkout(created, from: schedule)
        #expect(schedule.orderedItems.count == 4)
        #expect(schedule.orderedItems.map(\.orderIndex) == [0, 1, 2, 3])
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.name).sorted() == ["A", "B", "C"])
    }

    @Test("Raspored se vraća na stanje prije uređivanja: polja, niz i izmjene ciklusa")
    func restoresSchedule() throws {
        let context = try makeContext()
        let engine = ScheduleEngine(context: context)
        let (schedule, templates) = try abcSchedule(in: context, cycles: 4)
        try engine.skipNextWorkout(of: schedule)
        let before = schedule.orderedItems.map(\.id)
        let snapshot = try ScheduleSnapshot(schedule, context: context)

        schedule.name = "Promijenjeno"
        schedule.cycleCount = nil
        schedule.reminderMinutes = 7 * 60
        try engine.setActive(false, for: schedule)
        try engine.removeItem(schedule.orderedItems[2])
        try engine.addWorkout(templates[0], to: schedule)
        try engine.moveItems(in: schedule, from: IndexSet(integer: 0), to: 3)
        try engine.unskip(try #require(try engine.skippedWorkouts(of: schedule).first).change, in: schedule)

        try snapshot.restore(schedule, in: context)
        #expect(schedule.name == "ABC")
        #expect(schedule.cycleCount == 4)
        #expect(schedule.reminderMinutes == nil)
        #expect(schedule.isActive)
        #expect(schedule.orderedItems.map(\.id) == before)
        #expect(try engine.skippedWorkouts(of: schedule).map(\.templateName) == ["A"])
        #expect(try engine.nextWorkout(of: schedule)?.template.name == "B")
        #expect(try context.fetch(FetchDescriptor<ScheduleItem>()).count == 4)
    }

    @Test("Trening se vraća na stanje prije uređivanja: naziv, vježbe i serije")
    func restoresTemplate() throws {
        let context = try makeContext()
        let engine = TemplateEngine(context: context)
        let workout = try template("Gornji dio", in: context, exercises: [bench, row])
        let benchExercise = try #require(workout.orderedExercises.first)
        benchExercise.orderedSets.first?.targetReps = 8
        try context.save()
        let setCount = benchExercise.orderedSets.count
        let snapshot = TemplateSnapshot(workout)

        workout.name = "Drugo"
        benchExercise.orderedSets.first?.targetReps = 12
        _ = try engine.addSet(to: benchExercise)
        try engine.removeExercise(workout.orderedExercises[1])
        try engine.addExercise(curl, inputType: .weightReps, to: workout)
        try engine.moveExercises(in: workout, from: IndexSet(integer: 0), to: 2)

        try snapshot.restore(workout, in: context)
        #expect(workout.name == "Gornji dio")
        #expect(workout.orderedExercises.map(\.exerciseName) == [bench.name, row.name])
        let restored = try #require(workout.orderedExercises.first)
        #expect(restored.orderedSets.count == setCount)
        #expect(restored.orderedSets.first?.targetReps == 8)
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).count == 2)
    }
}
