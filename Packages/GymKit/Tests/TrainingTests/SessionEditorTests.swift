import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Training

private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")
private let base = Date(timeIntervalSince1970: 1_800_000_000)

/// Odrađen trening s potiskom (80 × 8, 85 × 6) u spremniku koji dijele glavni kontekst i uređivač.
private func finishedSession() throws -> (ModelContainer, Stored) {
    let container = try GymPersistence.makeUserContainer(storage: .inMemory)
    let context = ModelContext(container)
    let engine = WorkoutEngine(context: context)
    let session = try engine.startSession(name: "Push", now: base)
    let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
    for set in exercise.orderedSets { try engine.removeSet(set, now: base) }
    for (weight, reps) in [(80.0, 8), (85.0, 6)] {
        let set = try engine.addSet(to: exercise, now: base)
        set.weightKg = weight
        set.reps = reps
        try engine.completeSet(set, defaultRestSeconds: 0, now: base.addingTimeInterval(60))
    }
    try engine.finishSession(session, now: base.addingTimeInterval(3600))
    return (container, Stored(id: session.id, modelID: session.persistentModelID))
}

/// Oznake spremljenog treninga, da test ne drži objekt iz konteksta koji je već nestao.
private struct Stored {
    let id: UUID
    let modelID: PersistentIdentifier
}

/// Isti trening u zasebnom kontekstu uređivača, bez automatskog spremanja.
private func editingCopy(of session: Stored, in container: ModelContainer) throws -> (SessionEditor, Session) {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let copy = try #require(context.model(for: session.modelID) as? Session)
    return (SessionEditor(context: context), copy)
}

/// Spremljeno stanje, čitano svježim kontekstom (kontekst mora živjeti dok se trening čita).
private func fetchSession(_ id: UUID, in context: ModelContext) throws -> Session {
    let sessions = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id }))
    return try #require(sessions.first)
}

@Suite("Uređivanje odrađenog treninga")
struct SessionEditorTests {

    @Test("Brisanje svih serija s udaljenošću briše i udaljenost treninga")
    func clearsDistance() throws {
        let container = try GymPersistence.makeUserContainer(storage: .inMemory)
        let context = ModelContext(container)
        let engine = WorkoutEngine(context: context)
        let session = try engine.startSession(name: "Kondicija", now: base)
        let pressing = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        for set in pressing.orderedSets { try engine.removeSet(set, now: base) }
        let pressSet = try engine.addSet(to: pressing, now: base)
        pressSet.weightKg = 80
        pressSet.reps = 8
        try engine.completeSet(pressSet, defaultRestSeconds: 0, now: base.addingTimeInterval(60))
        let rowing = try engine.addExercise(row, inputType: .durationDistance, to: session, now: base)
        for set in rowing.orderedSets { try engine.removeSet(set, now: base) }
        let rowSet = try engine.addSet(to: rowing, now: base)
        rowSet.durationSeconds = 300
        rowSet.distanceMeters = 1000
        try engine.completeSet(rowSet, defaultRestSeconds: 0, now: base.addingTimeInterval(120))
        try engine.finishSession(session, now: base.addingTimeInterval(3600))
        #expect(session.distanceMeters == 1000)

        let stored = Stored(id: session.id, modelID: session.persistentModelID)
        let (editor, copy) = try editingCopy(of: stored, in: container)
        let copiedRowing = try #require(copy.orderedExercises.first { $0.exercise.key == row.key })
        editor.removeExercise(copiedRowing)
        try editor.save(copy)

        let reader = ModelContext(container)
        #expect(try fetchSession(stored.id, in: reader).distanceMeters == nil)
    }

    @Test("Spremljene izmjene: naziv, vrijednosti, nova serija i nova vježba")
    func savesChanges() throws {
        let (container, session) = try finishedSession()
        let reader = ModelContext(container)
        let (editor, copy) = try editingCopy(of: session, in: container)
        copy.name = "  Push A  "
        let pressing = copy.orderedExercises[0]
        pressing.orderedSets[1].reps = 7
        // Nova serija preuzima zadnje vrijednosti i odmah je završena, s vremenom kraja treninga.
        let added = editor.addSet(to: pressing)
        #expect(added.weightKg == 85 && added.reps == 7)
        #expect(added.completedAt == copy.endedAt)
        let rowing = editor.addExercise(row, inputType: .weightReps, to: copy)
        let set = rowing.orderedSets[0]
        set.weightKg = 50
        set.reps = 10
        try editor.toggleCompleted(set)
        try editor.save(copy)

        let saved = try fetchSession(session.id, in: reader)
        #expect(saved.name == "Push A")
        #expect(saved.orderedExercises.map(\.exerciseName) == ["Potisak s klupe", "Veslanje"])
        #expect(saved.orderedExercises[0].orderedSets.map(\.reps) == [8, 7, 7])
        // Prazne serije nove vježbe se ne spremaju.
        #expect(saved.orderedExercises[1].orderedSets.count == 1)
        #expect(saved.orderedExercises[1].orderedSets[0].orderIndex == 0)
    }

    @Test("Bez spremanja odrađeni trening ostaje kakav je bio")
    func discardsWithoutSave() throws {
        let (container, session) = try finishedSession()
        let reader = ModelContext(container)
        let (editor, copy) = try editingCopy(of: session, in: container)
        copy.name = "Drugo"
        editor.removeSet(copy.orderedExercises[0].orderedSets[0])
        editor.addExercise(row, inputType: .weightReps, to: copy)

        let saved = try fetchSession(session.id, in: reader)
        #expect(saved.name == "Push")
        #expect(saved.orderedExercises.count == 1)
        #expect(saved.orderedExercises[0].orderedSets.count == 2)
    }

    @Test("Obrisana vježba i serija nestaju, a redoslijed se slaže iznova")
    func removesExerciseAndSet() throws {
        let (container, session) = try finishedSession()
        let reader = ModelContext(container)
        let (editor, copy) = try editingCopy(of: session, in: container)
        let rowing = editor.addExercise(row, inputType: .weightReps, to: copy)
        rowing.orderedSets[0].weightKg = 40
        rowing.orderedSets[0].reps = 12
        try editor.toggleCompleted(rowing.orderedSets[0])
        editor.removeSet(copy.orderedExercises[0].orderedSets[0])
        editor.removeExercise(copy.orderedExercises[0])
        try editor.save(copy)

        let saved = try fetchSession(session.id, in: reader)
        #expect(saved.orderedExercises.map(\.exerciseName) == ["Veslanje"])
        #expect(saved.orderedExercises[0].orderIndex == 0)
    }

    @Test("Kvačica traži potpune vrijednosti, a trening bez završene serije se ne sprema")
    func validation() throws {
        let (container, session) = try finishedSession()
        let (editor, copy) = try editingCopy(of: session, in: container)
        let rowing = editor.addExercise(row, inputType: .weightReps, to: copy)
        #expect(throws: WorkoutError.setIncomplete) { try editor.toggleCompleted(rowing.orderedSets[0]) }
        for set in copy.orderedExercises[0].orderedSets { try editor.toggleCompleted(set) }
        #expect(throws: WorkoutError.nothingCompleted) { try editor.save(copy) }
    }

    @Test("Kraj treninga nije prije početka")
    func endNotBeforeStart() throws {
        let (container, session) = try finishedSession()
        let reader = ModelContext(container)
        let (editor, copy) = try editingCopy(of: session, in: container)
        copy.startedAt = base.addingTimeInterval(7200)
        try editor.save(copy)
        let saved = try fetchSession(session.id, in: reader)
        #expect(saved.endedAt == saved.startedAt)
    }

    @Test("Kontekst koji već drži trening nakon osvježavanja prikazuje spremljene izmjene")
    @MainActor
    func refreshesHoldingContext() throws {
        let (container, session) = try finishedSession()
        // Glavni kontekst drži trening kao detalji treninga dok je uređivač otvoren.
        let held = try fetchSession(session.id, in: container.mainContext)
        #expect(held.orderedExercises[0].orderedSets.map(\.reps) == [8, 6])

        let (editor, copy) = try editingCopy(of: session, in: container)
        copy.name = "Push A"
        copy.notes = "Lagano"
        copy.orderedExercises[0].orderedSets[1].reps = 3
        let rowing = editor.addExercise(row, inputType: .weightReps, to: copy)
        rowing.orderedSets[0].weightKg = 50
        rowing.orderedSets[0].reps = 10
        try editor.toggleCompleted(rowing.orderedSets[0])
        try editor.save(copy)

        SessionEditor.refresh(sessionId: session.id, in: container.mainContext)
        #expect(held.name == "Push A")
        #expect(held.notes == "Lagano")
        #expect(held.orderedExercises.map(\.exerciseName) == ["Potisak s klupe", "Veslanje"])
        #expect(held.orderedExercises[0].orderedSets.map(\.reps) == [8, 3])
        #expect(held.orderedExercises[1].orderedSets.map(\.reps) == [10])
    }
}
