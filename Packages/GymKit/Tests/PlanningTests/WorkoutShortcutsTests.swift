import Catalog
import Foundation
import Models
import SwiftData
import Testing
import Training
@testable import Planning

private let squat = ExerciseRef(catalogId: "squat", name: "Čučanj")
/// Petak 15. 1. 2027., 08:00 UTC.
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private func template(_ name: String, in context: ModelContext, exercises: [ExerciseRef] = [squat]) throws -> WorkoutTemplate {
    let engine = TemplateEngine(context: context)
    let result = try engine.createTemplate(name: name)
    for ref in exercises { try engine.addExercise(ref, inputType: .weightReps, to: result) }
    return result
}

/// Aktivan raspored A, B.
private func activeSchedule(in context: ModelContext) throws -> (Schedule, [WorkoutTemplate]) {
    let engine = ScheduleEngine(context: context)
    let templates = try ["A", "B"].map { try template($0, in: context) }
    let schedule = try engine.createSchedule(name: "AB")
    for item in templates { try engine.addWorkout(item, to: schedule) }
    try engine.setActive(true, for: schedule)
    return (schedule, templates)
}

private func completeFirstSet(of session: Session, in context: ModelContext) throws {
    let set = try #require(session.orderedExercises.first?.orderedSets.first)
    set.weightKg = 60
    set.reps = 5
    try WorkoutEngine(context: context).completeSet(set, defaultRestSeconds: 60, now: base)
}

/// Pokrenuti trening iz ishoda, ili nil kad trening nije pokrenut.
private func startedSession(_ result: ShortcutStartResult) -> Session? {
    if case .started(let session) = result { return session }
    return nil
}

@Suite("Prečaci: pokretanje i završavanje treninga")
struct WorkoutShortcutsTests {

    @Test("Bez odabranog treninga pokreće se prazan trening")
    func startEmpty() throws {
        let context = try makeContext()
        let session = try #require(startedSession(try WorkoutShortcuts(context: context).start(templateId: nil, emptyName: "Trening", now: base)))
        #expect(session.name == "Trening")
        #expect(session.templateId == nil)
        #expect(session.exercises?.isEmpty ?? true)
    }

    @Test("Spremljeni trening izvan rasporeda pokreće se s vježbama, bez rasporeda")
    func startTemplate() throws {
        let context = try makeContext()
        let push = try template("Push", in: context)
        let session = try #require(startedSession(try WorkoutShortcuts(context: context).start(templateId: push.id, emptyName: "Trening", now: base)))
        #expect(session.name == "Push")
        #expect(session.templateId == push.id)
        #expect(session.scheduleId == nil)
        #expect(session.orderedExercises.count == 1)
    }

    @Test("Trening iz aktivnog rasporeda pokreće se kao trening rasporeda, pa raspored napreduje")
    func startTemplateInSchedule() throws {
        let context = try makeContext()
        let (schedule, templates) = try activeSchedule(in: context)
        let shortcuts = WorkoutShortcuts(context: context)
        // B nije sljedeći (sljedeći je A), ali je u rasporedu.
        let session = try #require(startedSession(try shortcuts.start(templateId: templates[1].id, emptyName: "Trening", now: base)))
        #expect(session.scheduleId == schedule.id)
        try completeFirstSet(of: session, in: context)
        guard case .finished = try shortcuts.finishActive(now: base.addingTimeInterval(1800)) else {
            Issue.record("Trening nije završen")
            return
        }
        // B je odrađen u ciklusu, a sljedeći je i dalje A.
        #expect(try ScheduleEngine(context: context).nextWorkout(of: schedule)?.template.id == templates[0].id)
    }

    @Test("Obrisan ili prazan trening javlja grešku umjesto praznog treninga")
    func unavailableTemplate() throws {
        let context = try makeContext()
        let empty = try template("Prazan", in: context, exercises: [])
        let shortcuts = WorkoutShortcuts(context: context)
        #expect(throws: ShortcutError.templateUnavailable) {
            try shortcuts.start(templateId: empty.id, emptyName: "Trening", now: base)
        }
        #expect(throws: ShortcutError.templateUnavailable) {
            try shortcuts.start(templateId: UUID(), emptyName: "Trening", now: base)
        }
        #expect(try GymQueries(context: context).activeSession() == nil)
        #expect(try shortcuts.startableTemplates().isEmpty)
    }

    @Test("Dok je trening u tijeku, novi se ne pokreće")
    func alreadyActive() throws {
        let context = try makeContext()
        let (_, templates) = try activeSchedule(in: context)
        let shortcuts = WorkoutShortcuts(context: context)
        let first = try #require(startedSession(try shortcuts.start(templateId: nil, emptyName: "Trening", now: base)))
        for result in [
            try shortcuts.start(templateId: templates[0].id, emptyName: "Trening", now: base),
            try shortcuts.startNextScheduled(now: base),
        ] {
            guard case .alreadyActive(let active) = result else {
                Issue.record("Očekivan trening u tijeku, a dobiveno \(result)")
                continue
            }
            #expect(active.id == first.id)
        }
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 1)
    }

    @Test("Sljedeći trening iz rasporeda, a bez aktivnog rasporeda nema što pokrenuti")
    func nextScheduled() throws {
        let context = try makeContext()
        let shortcuts = WorkoutShortcuts(context: context)
        guard case .nothingScheduled = try shortcuts.startNextScheduled(now: base) else {
            Issue.record("Bez rasporeda ne smije se pokrenuti trening")
            return
        }
        let (schedule, templates) = try activeSchedule(in: context)
        let session = try #require(startedSession(try shortcuts.startNextScheduled(now: base)))
        #expect(session.templateId == templates[0].id)
        #expect(session.scheduleId == schedule.id)
    }

    @Test("Završavanje: bez treninga, trening na satu, trening bez završenih serija i uspjeh")
    func finish() throws {
        let context = try makeContext()
        let shortcuts = WorkoutShortcuts(context: context)
        guard case .noActiveWorkout = try shortcuts.finishActive(now: base) else {
            Issue.record("Bez treninga nema što završiti")
            return
        }

        let push = try template("Push", in: context)
        let session = try #require(startedSession(try shortcuts.start(templateId: push.id, emptyName: "Trening", now: base)))
        guard case .nothingCompleted = try shortcuts.finishActive(now: base) else {
            Issue.record("Trening bez završene serije ne smije se spremiti")
            return
        }
        #expect(session.state == .active)

        session.controllingDevice = .watch
        try completeFirstSet(of: session, in: context)
        guard case .ledByWatch = try shortcuts.finishActive(now: base) else {
            Issue.record("Trening koji vodi sat završava se na satu")
            return
        }
        #expect(session.state == .active)

        session.controllingDevice = .phone
        let end = base.addingTimeInterval(1800)
        guard case .finished(let finished) = try shortcuts.finishActive(now: end) else {
            Issue.record("Trening nije završen")
            return
        }
        #expect(finished.id == session.id)
        #expect(session.state == .finished)
        #expect(session.endedAt == end)
    }
}
