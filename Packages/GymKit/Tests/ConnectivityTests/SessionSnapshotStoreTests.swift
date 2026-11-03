import Catalog
import Foundation
import Models
import Planning
import SwiftData
import Testing
import Training
@testable import Connectivity

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

@Suite("Upis snimke sa sata u bazu")
struct SessionSnapshotStoreTests {

    @Test("Snimka se upisuje i čita natrag jednaka, a ponovljena ne stvara duplikate")
    func applyAndReadBack() throws {
        let context = try makeContext()
        let store = SessionSnapshotStore(context: context)
        let snapshot = sampleSnapshot()

        #expect(try store.apply(snapshot) == .applied(previousState: nil))
        #expect(try store.apply(snapshot) == .applied(previousState: .active))

        let sessions = try context.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 1)
        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).count == 4)
        #expect(SessionSnapshot(session: sessions[0]) == snapshot)
        #expect(sessions[0].controllingDevice == .watch)
        #expect(sessions[0].orderedExercises[0].exerciseKey == bench.key)
    }

    @Test("Starija snimka ne prepisuje noviju promjenu")
    func olderIgnored() throws {
        let context = try makeContext()
        let store = SessionSnapshotStore(context: context)
        var newer = sampleSnapshot()
        newer.updatedAt = base.addingTimeInterval(100)
        newer.exercises[0].sets[1].completedAt = base.addingTimeInterval(100)
        try store.apply(newer)

        var older = newer
        older.updatedAt = base.addingTimeInterval(50)
        older.exercises[0].sets[1].completedAt = nil
        #expect(try store.apply(older) == .ignoredOlder)
        #expect(try store.session(withID: newer.id)?.orderedExercises[0].orderedSets[1].isCompleted == true)

        // Uređaj koji vodi trening upisuje vlastito stanje bez obzira na vrijeme.
        #expect(try store.apply(older, force: true) == .applied(previousState: .active))
        #expect(try store.session(withID: newer.id)?.orderedExercises[0].orderedSets[1].isCompleted == false)
    }

    @Test("Završena snimka briše nezavršene serije, a odbačena cijeli trening")
    func finishAndDiscard() throws {
        let context = try makeContext()
        let store = SessionSnapshotStore(context: context)
        let active = sampleSnapshot()
        try store.apply(active)

        var engine = SnapshotEngine(snapshot: active)
        try engine.completeSet(active.exercises[0].orderedSets[1].id, defaultRestSeconds: 90, now: base.addingTimeInterval(60))
        try engine.finish(now: base.addingTimeInterval(1800))
        engine.recordHealth(workoutId: UUID(), activeEnergyKilocalories: 250, averageHeartRate: 120, now: base.addingTimeInterval(1801))
        #expect(try store.apply(engine.snapshot) == .applied(previousState: .active))

        let session = try #require(try store.session(withID: active.id))
        #expect(session.state == .finished)
        #expect(session.endedAt == base.addingTimeInterval(1800))
        // Kalorije i puls su u lokalnoj bazi, ne u treningu koji se sinkronizira.
        #expect(session.activeEnergyKilocalories == nil)
        #expect(session.averageHeartRate == nil)
        let local = try #require(try HealthLocalStore(context: context).values(forSession: session.id))
        #expect(local.activeEnergyKilocalories == 250)
        #expect(local.averageHeartRate == 120)
        #expect(store.snapshot(of: session).activeEnergyKilocalories == 250)
        #expect(session.healthKitWorkoutId != nil)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).count == 1)
        // Isti završni zapis stigne i drugim kanalom: ništa se ne mijenja.
        #expect(try store.apply(engine.snapshot) == .applied(previousState: .finished))
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 1)

        var discarded = sampleSnapshot()
        try store.apply(discarded)
        discarded.state = .discarded
        discarded.updatedAt = base.addingTimeInterval(10)
        #expect(try store.apply(discarded) == .discarded)
        #expect(try store.session(withID: discarded.id)?.state == .discarded)
        #expect(try store.purgeDiscarded() == 1)
        #expect(try store.session(withID: discarded.id) == nil)
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 1)
    }

    @Test("Trening s iPhonea u snimci i natrag kroz naredbe sa sata")
    func phoneControlledRoundTrip() throws {
        let context = try makeContext()
        let engine = WorkoutEngine(context: context)
        let session = try engine.startSession(name: "Push", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let snapshot = SessionSnapshot(session: session)
        #expect(snapshot.controllingDevice == .phone)
        #expect(snapshot.exercises[0].sets.count == WorkoutEngine.defaultWorkingSets)

        // Sat upiše težinu i ponavljanja i označi prvu seriju.
        var edited = snapshot
        edited.exercises[0].sets[0].weightKg = 70
        edited.exercises[0].sets[0].reps = 5
        edited.exercises[0].sets[0].completedAt = base.addingTimeInterval(30)
        let commands = SnapshotDiff.commands(from: snapshot, to: edited)
        let merged = SnapshotDiff.apply(commands, to: SessionSnapshot(session: session), at: base.addingTimeInterval(31))
        try SessionSnapshotStore(context: context).apply(merged, force: true)

        let first = exercise.orderedSets[0]
        #expect(first.weightKg == 70)
        #expect(first.reps == 5)
        #expect(first.isCompleted)
        #expect(session.lastActivityAt == base.addingTimeInterval(31))
        #expect(try context.fetch(FetchDescriptor<SetLog>()).count == WorkoutEngine.defaultWorkingSets)
    }
}

@Suite("Kontekst za sat")
struct WatchContextBuilderTests {

    /// Serije kakve bi dobio trening pokrenut na iPhoneu.
    private func startedSets(_ template: WorkoutTemplate, in context: ModelContext) throws -> [[PlannedSetPayload]] {
        let session = try TemplateStarter(context: context).start(template, now: base.addingTimeInterval(7200))
        defer { try? WorkoutEngine(context: context).discardSession(session) }
        return session.orderedExercises.map { exercise in
            exercise.orderedSets.map {
                PlannedSetPayload(kind: $0.kind, weightKg: $0.weightKg, reps: $0.reps, extraWeightKg: $0.extraWeightKg,
                                  durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters)
            }
        }
    }

    @Test("Serije u kontekstu jednake su serijama treninga pokrenutog na iPhoneu")
    func matchesTemplateStarter() throws {
        let context = try makeContext()
        // Povijest: veslanje s jednom warm-up i dvije radne serije.
        let workout = WorkoutEngine(context: context)
        let past = try workout.startSession(name: "Prije", now: base)
        let pastRow = try workout.addExercise(row, inputType: .weightReps, to: past, now: base)
        try workout.addSet(to: pastRow, kind: .warmUp, now: base)
        for (index, set) in pastRow.orderedSets.enumerated() {
            set.weightKg = Double(50 + index * 5)
            set.reps = 10 - index
            try workout.completeSet(set, defaultRestSeconds: 90, now: base)
        }
        try workout.finishSession(past, now: base.addingTimeInterval(600))

        // Predložak: veslanje bez ciljeva i potisak s ciljevima (2 serije, druga s 85 kg).
        let templates = TemplateEngine(context: context)
        let template = try templates.createTemplate(name: "Pull")
        try templates.addExercise(row, inputType: .weightReps, to: template)
        let benchEx = try templates.addExercise(bench, inputType: .weightReps, to: template)
        for set in benchEx.orderedSets { try templates.removeSet(set) }
        let first = try templates.addSet(to: benchEx, kind: .working)
        let second = try templates.addSet(to: benchEx, kind: .working)
        try templates.setTargets(first, weightKg: nil, reps: 8)
        try templates.setTargets(second, weightKg: 85, reps: nil)

        let payload = try WatchContextBuilder(context: context).make(now: base)
        let planned = try #require(payload.templates.first { $0.templateId == template.id })
        #expect(planned.exercises.map(\.exercise) == [row, bench])
        #expect(planned.exercises.map(\.sets) == (try startedSets(template, in: context)))
        #expect(payload.weightUnit == .kilograms)
        #expect(payload.defaultRestSeconds == 90)
    }

    @Test("Sljedeći trening rasporeda je u kontekstu s nazivom rasporeda i supersetom")
    func upcoming() throws {
        let context = try makeContext()
        let templates = TemplateEngine(context: context)
        let template = try templates.createTemplate(name: "Push")
        let first = try templates.addExercise(bench, inputType: .weightReps, to: template)
        let second = try templates.addExercise(row, inputType: .weightReps, to: template)
        try templates.makeSuperset([first, second], in: template)
        let schedules = ScheduleEngine(context: context)
        let schedule = try schedules.createSchedule(name: "PPL")
        try schedules.addWorkout(template, to: schedule)

        let payload = try WatchContextBuilder(context: context).make(now: base)
        let next = try #require(payload.upcoming.first)
        #expect(next.name == "Push")
        #expect(next.scheduleName == "PPL")
        #expect(next.scheduleId == schedule.id)
        #expect(next.exercises.map(\.supersetGroup) == [0, 0])

        let started = SnapshotEngine.start(next, device: .watch, now: base)
        #expect(started.exercises[0].supersetGroupId == started.exercises[1].supersetGroupId)
        #expect(started.exercises[0].supersetGroupId != nil)
    }
}
