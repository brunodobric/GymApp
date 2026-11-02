import Catalog
import Foundation
import SwiftData
import Testing
import Units
@testable import Models

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private let bench = ExerciseRef(catalogId: "bench-press", name: "Bench press")
private let squat = ExerciseRef(catalogId: "squat", name: "Squat")

/// Stvara završeni trening s jednom vježbom i zadanim serijama (težina, ponavljanja).
@discardableResult
private func makeSession(
    in context: ModelContext,
    exercise: ExerciseRef,
    startedAt: Date,
    state: SessionState = .finished,
    sets: [(Double, Int)] = [(80, 8)],
    removed: Bool = false
) -> Session {
    let session = Session(name: "Trening", startedAt: startedAt)
    session.state = state
    context.insert(session)
    let sessionExercise = SessionExercise(orderIndex: 0, exercise: exercise)
    sessionExercise.isRemoved = removed
    sessionExercise.session = session
    for (index, set) in sets.enumerated() {
        let log = SetLog(orderIndex: index)
        log.weightKg = set.0
        log.reps = set.1
        log.exercise = sessionExercise
    }
    return session
}

@Suite("Modeli")
struct ModelsTests {

    @Test("Predložak čuva redoslijed vježbi i serija preko orderIndex")
    func templateOrdering() throws {
        let context = try makeContext()
        let template = WorkoutTemplate(name: "Push")
        context.insert(template)
        for (index, ref) in [squat, bench].enumerated().reversed() {
            let exercise = TemplateExercise(orderIndex: index, exercise: ref)
            exercise.template = template
            for setIndex in (0..<3).reversed() {
                let set = TemplateSet(orderIndex: setIndex, targetWeightKg: 60 + Double(setIndex) * 5, targetReps: 8)
                set.exercise = exercise
            }
        }
        try context.save()

        let ordered = template.orderedExercises
        #expect(ordered.map(\.exerciseName) == ["Squat", "Bench press"])
        #expect(ordered[0].orderedSets.map(\.orderIndex) == [0, 1, 2])
        #expect(ordered[0].orderedSets.map(\.targetWeightKg) == [60, 65, 70])
    }

    @Test("Brisanje predloška ne briše odrađene treninge")
    func deletingTemplateKeepsSessions() throws {
        let context = try makeContext()
        let template = WorkoutTemplate(name: "Pull")
        context.insert(template)
        let templateExercise = TemplateExercise(orderIndex: 0, exercise: bench)
        templateExercise.template = template

        let session = makeSession(in: context, exercise: bench, startedAt: Date())
        session.templateId = template.id
        try context.save()

        context.delete(template)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
        let sessions = try context.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 1)
        #expect(sessions[0].orderedExercises.count == 1)
        #expect(sessions[0].orderedExercises[0].orderedSets.count == 1)
    }

    @Test("Brisanje rasporeda ne briše treninge ni predloške")
    func deletingScheduleKeepsTemplates() throws {
        let context = try makeContext()
        let template = WorkoutTemplate(name: "Legs")
        context.insert(template)
        let schedule = Schedule(name: "PPL")
        context.insert(schedule)
        let item = ScheduleItem(orderIndex: 0, kind: .workout, workoutTemplateId: template.id)
        item.schedule = schedule
        makeSession(in: context, exercise: squat, startedAt: Date())
        try context.save()

        context.delete(schedule)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ScheduleItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 1)
    }

    @Test("Brisanje treninga briše njegove vježbe i serije")
    func deletingSessionCascades() throws {
        let context = try makeContext()
        let session = makeSession(in: context, exercise: bench, startedAt: Date(), sets: [(80, 8), (85, 6)])
        try context.save()

        context.delete(session)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    }

    @Test("Ključ vježbe razlikuje katalog i vlastite vježbe")
    func exerciseRefKey() {
        let id = UUID()
        #expect(bench.key == "c:bench-press")
        #expect(ExerciseRef(customExerciseId: id, name: "Moja").key == "u:\(id.uuidString)")
    }

    @Test("Zamjena vježbe u treningu ažurira ključ za upite")
    func exerciseKeyFollowsRef() {
        let exercise = SessionExercise(orderIndex: 0, exercise: bench)
        #expect(exercise.exerciseKey == "c:bench-press")
        exercise.exercise = squat
        #expect(exercise.exerciseKey == "c:squat")
        #expect(exercise.exerciseName == "Squat")
    }

    @Test("RPE prihvaća samo 1 do 10 u koracima od 0,5")
    func rpeValidation() {
        for valid in [1.0, 1.5, 7.5, 10.0] { #expect(RPE.isValid(valid)) }
        for invalid in [0.0, 0.5, 7.25, 10.5, 11.0, -1.0] { #expect(!RPE.isValid(invalid)) }
        #expect(RPE.rir(fromRPE: 8.5) == 1.5)
        #expect(RPE.rpe(fromRIR: 2) == 8)
    }

    @Test("Postavke imaju tvorničke vrijednosti i pretvaraju popis ploča")
    func settingsDefaults() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        let settings = try queries.settings()
        #expect(settings.weightUnit == .kilograms)
        #expect(settings.defaultRestSeconds == 90)
        #expect(settings.effortScale == .rpe)
        #expect(settings.availablePlatesKg == [1.25, 2.5, 5, 10, 15, 20, 25])

        settings.weightUnit = .pounds
        settings.availablePlatesKg = [2.5, 5]
        #expect(settings.availablePlatesRaw == "2.5,5.0")
        // Drugi poziv vraća isti zapis, ne stvara novi.
        #expect(try queries.settings().id == settings.id)
    }

    @Test("Težina se u bazi čuva u kilogramima")
    func weightStoredInKilograms() throws {
        let context = try makeContext()
        let log = SetLog(orderIndex: 0)
        log.weightKg = WeightConversion.kilograms(from: 225, in: .pounds)
        context.insert(log)
        try context.save()
        let stored = try #require(try context.fetch(FetchDescriptor<SetLog>()).first?.weightKg)
        #expect(abs(stored - 102.0582) < 0.001)
    }

    @Test("Vrijednosti s nepoznatim tekstom vraćaju sigurnu zadanu")
    func unknownRawValues() {
        let set = SetLog(orderIndex: 0)
        set.kindRaw = "nepoznato"
        #expect(set.kind == .working)
        let session = Session(name: "x")
        session.stateRaw = "nepoznato"
        #expect(session.state == .finished)
    }
}

@Suite("Upiti")
struct QueriesTests {

    @Test("Aktivni trening je onaj u tijeku, najnoviji")
    func activeSession() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        #expect(try queries.activeSession() == nil)

        makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 1000), state: .finished)
        makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 2000), state: .active)
        let newest = makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 3000), state: .active)
        makeSession(in: context, exercise: bench, startedAt: Date(timeIntervalSince1970: 4000), state: .discarded)
        try context.save()

        #expect(try queries.activeSession()?.id == newest.id)
    }

    @Test("Treninzi u rasponu: samo završeni, od najnovijeg")
    func sessionsInRange() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let before = makeSession(in: context, exercise: bench, startedAt: base - day)
        let first = makeSession(in: context, exercise: bench, startedAt: base)
        let second = makeSession(in: context, exercise: bench, startedAt: base + day)
        makeSession(in: context, exercise: bench, startedAt: base + 2 * day, state: .active)
        makeSession(in: context, exercise: bench, startedAt: base + 3 * day, state: .discarded)
        let after = makeSession(in: context, exercise: bench, startedAt: base + 10 * day)
        try context.save()

        let result = try queries.finishedSessions(from: base, to: base + 5 * day)
        #expect(result.map(\.id) == [second.id, first.id])
        #expect(!result.contains { $0.id == before.id || $0.id == after.id })
    }

    @Test("Zadnje izvođenje vježbe preskače izbačene, nezavršene i druge vježbe")
    func lastPerformance() throws {
        let context = try makeContext()
        let queries = GymQueries(context: context)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        makeSession(in: context, exercise: bench, startedAt: base, sets: [(70, 8)])
        makeSession(in: context, exercise: bench, startedAt: base + 100, sets: [(80, 8), (85, 8)])
        makeSession(in: context, exercise: bench, startedAt: base + 200, sets: [(999, 1)], removed: true)
        makeSession(in: context, exercise: bench, startedAt: base + 300, state: .active, sets: [(999, 1)])
        makeSession(in: context, exercise: squat, startedAt: base + 400, sets: [(999, 1)])
        try context.save()

        let last = try #require(try queries.lastPerformance(of: bench))
        #expect(last.orderedSets.map(\.weightKg) == [80, 85])
        #expect(try queries.lastPerformance(of: ExerciseRef(catalogId: "nepoznato", name: "?")) == nil)
    }

    @Test("Duplikati po UUID-u se uklanjaju, a različiti zapisi ostaju")
    func deduplication() throws {
        let context = try makeContext()
        let shared = UUID()
        for _ in 0..<3 {
            let measurement = BodyMeasurement(kind: .weight, value: 80)
            measurement.id = shared
            context.insert(measurement)
        }
        context.insert(BodyMeasurement(kind: .weight, value: 81))
        try context.save()

        let removed = try Deduplication.removeDuplicates(of: BodyMeasurement.self, id: \.id, in: context)
        #expect(removed == 2)
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).count == 2)
        #expect(try Deduplication.removeAllDuplicates(in: context) == 0)
    }
}

@Suite("Vlastite vježbe")
struct CustomExerciseTests {

    @Test("Vlastita vježba bez povijesti se briše")
    func deletedWithoutHistory() throws {
        let context = try makeContext()
        let exercise = CustomExercise(name: "Moja vježba")
        context.insert(exercise)
        try context.save()

        #expect(try CustomExerciseStore.remove(exercise, in: context) == .deleted)
        #expect(try context.fetch(FetchDescriptor<CustomExercise>()).isEmpty)
    }

    @Test("Vlastita vježba s poviješću se arhivira, a povijest ostaje")
    func archivedWithHistory() throws {
        let context = try makeContext()
        let exercise = CustomExercise(name: "Moja vježba")
        context.insert(exercise)
        makeSession(in: context, exercise: exercise.ref, startedAt: Date())
        try context.save()

        #expect(try CustomExerciseStore.remove(exercise, in: context) == .archived)
        let stored = try context.fetch(FetchDescriptor<CustomExercise>())
        #expect(stored.count == 1)
        #expect(stored[0].isArchived)
        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).count == 1)
    }

    @Test("Vlastita vježba u predlošku se također arhivira")
    func archivedWhenInTemplate() throws {
        let context = try makeContext()
        let exercise = CustomExercise(name: "Moja vježba")
        context.insert(exercise)
        let template = WorkoutTemplate(name: "Dan A")
        context.insert(template)
        let templateExercise = TemplateExercise(orderIndex: 0, exercise: exercise.ref)
        templateExercise.template = template
        try context.save()

        #expect(try CustomExerciseStore.remove(exercise, in: context) == .archived)
    }

    @Test("Svojstva vlastite vježbe i sažetak")
    func summaryAndAccessors() {
        let exercise = CustomExercise(name: "Povlačenje užeta", inputType: .duration)
        exercise.category = .back
        exercise.equipment = .other
        exercise.muscles = [.lats, .biceps]

        #expect(exercise.inputType == .duration)
        #expect(exercise.muscles == [.lats, .biceps])
        let summary = exercise.summary
        #expect(summary.isCustom)
        #expect(summary.category == .back)
        #expect(summary.ref.customExerciseId == exercise.id)
        #expect(summary.ref.key == "u:\(exercise.id.uuidString)")
    }
}
