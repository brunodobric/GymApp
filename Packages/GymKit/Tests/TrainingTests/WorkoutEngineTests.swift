import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Training

private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func makeEngine() throws -> (WorkoutEngine, ModelContext) {
    let context = ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
    return (WorkoutEngine(context: context), context)
}

/// Odradi i završi trening s jednom vježbom: svaka serija je (težina, ponavljanja).
@discardableResult
private func finishedWorkout(
    _ engine: WorkoutEngine, ref: ExerciseRef = bench, at start: Date, sets: [(Double, Int)]
) throws -> Session {
    let session = try engine.startSession(name: "Trening", now: start)
    let exercise = try engine.addExercise(ref, inputType: .weightReps, to: session, now: start)
    // Višak serija koje je addExercise stvorio se miče, pa ostaju točno zadane.
    for set in exercise.orderedSets { try engine.removeSet(set, now: start) }
    for values in sets {
        let set = try engine.addSet(to: exercise, now: start)
        set.weightKg = values.0
        set.reps = values.1
        try engine.completeSet(set, defaultRestSeconds: 90, now: start.addingTimeInterval(60))
    }
    try engine.finishSession(session, now: start.addingTimeInterval(3600))
    return session
}

@Suite("Tijek treninga")
struct WorkoutEngineTests {

    @Test("Prethodne vrijednosti su završene serije zadnjeg treninga s tom vježbom")
    func previousSetValues() throws {
        let (engine, context) = try makeEngine()
        let queries = GymQueries(context: context)
        #expect(try queries.previousSetValues(of: bench).isEmpty)
        try finishedWorkout(engine, at: base, sets: [(60, 10)])
        try finishedWorkout(engine, at: base + 86_400, sets: [(70, 8), (75, 6)])
        let values = try queries.previousSetValues(of: bench)
        #expect(values.map(\.weightKg) == [70, 75])
        #expect(values.map(\.reps) == [8, 6])
        #expect(try queries.previousSetValues(of: row).isEmpty)
    }

    @Test("Samo jedan aktivan trening istovremeno")
    func singleActive() throws {
        let (engine, _) = try makeEngine()
        try engine.startSession(name: "A", now: base)
        #expect(throws: WorkoutError.alreadyActive) { try engine.startSession(name: "B", now: base) }
    }

    @Test("Vježba bez povijesti dobiva tri prazne radne serije")
    func firstTimeExercise() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        #expect(exercise.orderedSets.count == WorkoutEngine.defaultWorkingSets)
        #expect(exercise.orderedSets.allSatisfy { $0.kind == .working && $0.weightKg == nil })
    }

    @Test("Nova vježba preuzima serije i vrijednosti iz zadnjeg treninga")
    func smartDefaultsFromHistory() throws {
        let (engine, _) = try makeEngine()
        try finishedWorkout(engine, at: base, sets: [(80, 8), (85, 8), (90, 6)])
        let session = try engine.startSession(name: "B", now: base.addingTimeInterval(86_400))
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base.addingTimeInterval(86_400))
        #expect(exercise.orderedSets.map(\.weightKg) == [80, 85, 90])
        #expect(exercise.orderedSets.map(\.reps) == [8, 8, 6])
        #expect(exercise.orderedSets.allSatisfy { !$0.isCompleted })
    }

    @Test("Dodana serija preko povijesti uzima zadnju vrijednost, a bez povijesti prethodnu seriju")
    func addedSetDefaults() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        exercise.orderedSets[2].weightKg = 70
        exercise.orderedSets[2].reps = 10
        let added = try engine.addSet(to: exercise, now: base)
        #expect(added.weightKg == 70)
        #expect(added.reps == 10)
        #expect(added.orderIndex == 3)
    }

    @Test("Zagrijavanje se dodaje ispred prve neodrađene serije, a radna serija na kraj")
    func warmUpGoesBeforeFirstIncompleteSet() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let first = exercise.orderedSets[0]
        first.weightKg = 60
        first.reps = 10
        try engine.completeSet(first, defaultRestSeconds: 90, now: base)

        let warmUp = try engine.addSet(to: exercise, kind: .warmUp, now: base)
        #expect(exercise.orderedSets.map(\.kind) == [.working, .warmUp, .working, .working])
        #expect(warmUp.orderIndex == 1)
        #expect(exercise.orderedSets.map(\.orderIndex) == [0, 1, 2, 3])

        let working = try engine.addSet(to: exercise, kind: .working, now: base)
        #expect(working.orderIndex == 4)

        // Kad su sve serije odrađene, zagrijavanje ide na kraj.
        for set in exercise.orderedSets where !set.isCompleted {
            set.weightKg = 40
            set.reps = 10
            try engine.completeSet(set, defaultRestSeconds: 90, now: base)
        }
        let last = try engine.addSet(to: exercise, kind: .warmUp, now: base)
        #expect(last.orderIndex == 5)
        #expect(exercise.orderedSets.last?.id == last.id)
    }

    @Test("Označavanje serije traži sve vrijednosti i pokreće rest timer")
    func completeSetStartsRest() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let set = exercise.orderedSets[0]

        #expect(throws: WorkoutError.setIncomplete) { try engine.completeSet(set, defaultRestSeconds: 90, now: base) }
        #expect(!set.isCompleted)

        set.weightKg = 80
        set.reps = 8
        let timer = try engine.completeSet(set, defaultRestSeconds: 90, now: base)
        #expect(set.isCompleted)
        #expect(timer?.totalSeconds == 90)
        #expect(engine.restTimer(of: session)?.endsAt == base.addingTimeInterval(90))

        let adjusted = try engine.adjustRest(of: session, bySeconds: 10, now: base.addingTimeInterval(30))
        #expect(adjusted?.endsAt == base.addingTimeInterval(100))
        #expect(engine.restTimer(of: session)?.endsAt == base.addingTimeInterval(100))

        try engine.cancelRest(of: session, now: base)
        #expect(engine.restTimer(of: session) == nil)
    }

    @Test("Pauza vježbe nadjačava zadanu")
    func exerciseRestOverride() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, restSeconds: 150, now: base)
        let set = exercise.orderedSets[0]
        set.weightKg = 80
        set.reps = 8
        #expect(try engine.completeSet(set, defaultRestSeconds: 90, now: base)?.totalSeconds == 150)
    }

    @Test("Superset: bez pauze nakon prve vježbe, zadana nakon zadnje")
    func supersetRest() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let first = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let second = try engine.addExercise(row, inputType: .weightReps, to: session, now: base)
        try engine.makeSuperset([first, second], in: session, now: base)

        for set in [first.orderedSets[0], second.orderedSets[0]] {
            set.weightKg = 50
            set.reps = 10
        }
        #expect(try engine.completeSet(first.orderedSets[0], defaultRestSeconds: 90, now: base) == nil)
        #expect(try engine.completeSet(second.orderedSets[0], defaultRestSeconds: 90, now: base)?.totalSeconds == 90)
    }

    @Test("Superset stavlja vježbe jednu do druge, first samac se raspušta")
    func supersetGrouping() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let first = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let middle = try engine.addExercise(ExerciseRef(catalogId: "squat", name: "Čučanj"), inputType: .weightReps, to: session, now: base)
        let last = try engine.addExercise(row, inputType: .weightReps, to: session, now: base)

        try engine.makeSuperset([first, last], in: session, now: base)
        #expect(engine.visibleExercises(in: session).map(\.id) == [first.id, last.id, middle.id])
        #expect(first.supersetGroupId != nil && first.supersetGroupId == last.supersetGroupId)
        #expect(engine.group(of: first).map(\.id) == [first.id, last.id])

        try engine.removeFromSuperset(last, now: base)
        #expect(first.supersetGroupId == nil)
        #expect(last.supersetGroupId == nil)

        #expect(throws: WorkoutError.needsTwoExercises) { try engine.makeSuperset([first], in: session, now: base) }
    }

    @Test("Izbacivanje vježbe se poništava i redoslijed se mijenja povlačenjem")
    func removeRestoreMove() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let first = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let second = try engine.addExercise(row, inputType: .weightReps, to: session, now: base)
        let third = try engine.addExercise(ExerciseRef(catalogId: "squat", name: "Čučanj"), inputType: .weightReps, to: session, now: base)

        try engine.moveExercises(in: session, from: IndexSet(integer: 2), to: 0, now: base)
        #expect(engine.visibleExercises(in: session).map(\.id) == [third.id, first.id, second.id])

        try engine.removeExercise(first, now: base)
        #expect(engine.visibleExercises(in: session).map(\.id) == [third.id, second.id])
        #expect(engine.removedExercises(in: session).map(\.id) == [first.id])

        try engine.restoreExercise(first, now: base)
        #expect(engine.visibleExercises(in: session).map(\.id) == [third.id, second.id, first.id])
        #expect(engine.removedExercises(in: session).isEmpty)
    }

    @Test("Brisanje serije se poništava: serija se vraća na isto mjesto s istim vrijednostima")
    func removeRestoreSet() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let sets = exercise.orderedSets
        let middle = sets[1]
        middle.weightKg = 80
        middle.reps = 8
        middle.rpe = 8.5
        try engine.completeSet(middle, defaultRestSeconds: 90, now: base.addingTimeInterval(60))
        let ids = sets.map(\.id)

        let removed = try engine.removeSet(middle, now: base.addingTimeInterval(120))
        #expect(exercise.orderedSets.map(\.id) == [ids[0], ids[2]])
        #expect(exercise.orderedSets.map(\.orderIndex) == [0, 1])
        #expect(removed.position == 1)
        #expect(session.lastActivityAt == base.addingTimeInterval(120))

        let restored = try engine.restoreSet(removed, to: exercise, now: base.addingTimeInterval(130))
        #expect(exercise.orderedSets.map(\.id) == ids)
        #expect(exercise.orderedSets.map(\.orderIndex) == [0, 1, 2])
        #expect(restored.values == SetValues(kind: .working, weightKg: 80, reps: 8, rpe: 8.5))
        #expect(restored.completedAt == base.addingTimeInterval(60))
        #expect(session.lastActivityAt == base.addingTimeInterval(130))
    }

    @Test("Vraćena serija ide na kraj ako je vježba u međuvremenu ostala bez serija")
    func restoreSetPastEnd() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let last = try #require(exercise.orderedSets.last)
        let removed = try engine.removeSet(last, now: base)
        for set in exercise.orderedSets { try engine.removeSet(set, now: base) }

        try engine.restoreSet(removed, to: exercise, now: base)
        #expect(exercise.orderedSets.map(\.id) == [removed.id])
        #expect(exercise.orderedSets.map(\.orderIndex) == [0])
    }

    @Test("Završetak briše nezavršene serije, prazne i izbačene vježbe")
    func finishCleansUp() throws {
        let (engine, context) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let kept = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let empty = try engine.addExercise(row, inputType: .weightReps, to: session, now: base)
        let removed = try engine.addExercise(ExerciseRef(catalogId: "squat", name: "Čučanj"), inputType: .weightReps, to: session, now: base)
        let set = kept.orderedSets[0]
        set.weightKg = 80
        set.reps = 8
        try engine.completeSet(set, defaultRestSeconds: 90, now: base)
        try engine.removeExercise(removed, now: base)

        try engine.finishSession(session, notes: "Dobro", now: base.addingTimeInterval(1800))

        #expect(session.state == .finished)
        #expect(session.notes == "Dobro")
        #expect(session.endedAt == base.addingTimeInterval(1800))
        #expect(engine.restTimer(of: session) == nil)
        let exercises = try context.fetch(FetchDescriptor<SessionExercise>())
        #expect(exercises.map(\.id) == [kept.id])
        #expect(exercises[0].orderedSets.count == 1)
        _ = empty
    }

    @Test("Trening bez ijedne završene serije ne može se spremiti i ostaje netaknut")
    func nothingCompleted() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        #expect(throws: WorkoutError.nothingCompleted) { try engine.finishSession(session, now: base) }
        #expect(session.state == .active)
        #expect(exercise.orderedSets.count == WorkoutEngine.defaultWorkingSets)
    }

    @Test("Odbacivanje briše trening sa svim serijama")
    func discard() throws {
        let (engine, context) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        try engine.discardSession(session)
        #expect(try context.fetch(FetchDescriptor<Session>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    }

    @Test("Prekinuti trening se pronalazi i rest timer preživi ponovno otvaranje")
    func recoveryOfActiveSession() throws {
        let (engine, context) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let set = exercise.orderedSets[0]
        set.weightKg = 80
        set.reps = 8
        try engine.completeSet(set, defaultRestSeconds: 120, now: base)

        // "Ponovno pokretanje": novi engine nad istim kontekstom, sve se čita iz baze.
        let restarted = WorkoutEngine(context: context)
        let found = try #require(try GymQueries(context: context).activeSession())
        #expect(found.id == session.id)
        let timer = try #require(restarted.restTimer(of: found))
        #expect(timer.remaining(at: base.addingTimeInterval(100)) == 20)
        #expect(timer.isExpired(at: base.addingTimeInterval(200)))
        #expect(restarted.lastCompletedSetAt(in: found) == base)
    }

    @Test("Zaboravljeni trening se zatvara na zadnju završenu seriju")
    func closeStale() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let set = exercise.orderedSets[0]
        set.weightKg = 80
        set.reps = 8
        try engine.completeSet(set, defaultRestSeconds: 90, now: base.addingTimeInterval(600))
        try engine.closeStaleSession(session)
        #expect(session.state == .finished)
        #expect(session.endedAt == base.addingTimeInterval(600))
    }

    @Test("Sažetak: trajanje, volumen bez warm-upa i rekordi samo prema ranijim treninzima")
    func summary() throws {
        let (engine, _) = try makeEngine()
        // Rekordi kreću od četvrtog izvođenja vježbe (kalibracija).
        for index in 0..<3 {
            try finishedWorkout(engine, at: base.addingTimeInterval(Double(index) * 3600), sets: [(80, 8)])
        }

        let start = base.addingTimeInterval(86_400)
        let session = try engine.startSession(name: "B", now: start)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: start)
        for set in exercise.orderedSets { try engine.removeSet(set, now: start) }
        let warmUp = try engine.addSet(to: exercise, kind: .warmUp, now: start)
        warmUp.weightKg = 40
        warmUp.reps = 10
        let working = try engine.addSet(to: exercise, kind: .working, now: start)
        working.weightKg = 85
        working.reps = 8
        try engine.completeSet(warmUp, defaultRestSeconds: 90, now: start.addingTimeInterval(60))
        try engine.completeSet(working, defaultRestSeconds: 90, now: start.addingTimeInterval(300))
        try engine.finishSession(session, now: start.addingTimeInterval(1800))

        let summary = try engine.summary(of: session)
        #expect(summary.durationSeconds == 1800)
        #expect(summary.completedSets == 2)
        #expect(summary.totalVolumeKg == 680)
        #expect(summary.hardSets == 1)
        let records = try #require(summary.records.first)
        #expect(records.exerciseName == "Potisak s klupe")
        #expect(records.records.contains { $0.kind == .maxWeight && $0.value == 85 })
        // Istaknut je jedan rekord vježbe (procjena 1RM), ostali su prebrojani.
        #expect(summary.highlights.map(\.record.kind) == [.estimatedOneRepMax])
        #expect(summary.otherRecordsCount == records.records.count - 1)

        let excluded = try engine.summary(of: session, excludedExercises: [bench.key])
        #expect(excluded.records.isEmpty && excluded.highlights.isEmpty)
    }

    @Test("Zadnje izvođenje koristi samo završene treninge, ne aktivni")
    func historyIgnoresActive() throws {
        let (engine, _) = try makeEngine()
        let first = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: first, now: base)
        let set = exercise.orderedSets[0]
        set.weightKg = 100
        set.reps = 5
        try engine.completeSet(set, defaultRestSeconds: 90, now: base)
        try engine.discardSession(first)

        let second = try engine.startSession(name: "B", now: base)
        let fresh = try engine.addExercise(bench, inputType: .weightReps, to: second, now: base)
        #expect(fresh.orderedSets.allSatisfy { $0.weightKg == nil })
    }

    @Test("Kardio trening sprema ukupnu udaljenost završenih serija")
    func cardioDistance() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "Kardio", now: base)
        let run = try engine.addExercise(row, inputType: .durationDistance, to: session, now: base)
        for set in run.orderedSets { try engine.removeSet(set, now: base) }
        for meters in [3000.0, 2000.0] {
            let set = try engine.addSet(to: run, now: base)
            set.durationSeconds = 900
            set.distanceMeters = meters
            try engine.completeSet(set, defaultRestSeconds: 60, now: base.addingTimeInterval(900))
        }
        let unfinished = try engine.addSet(to: run, now: base)
        unfinished.durationSeconds = 60
        unfinished.distanceMeters = 999
        try engine.finishSession(session, now: base.addingTimeInterval(2000))
        #expect(session.distanceMeters == 5000)
    }
}
