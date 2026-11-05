import Catalog
import Foundation
import Models
import SwiftData
import Testing
import Training
import Units
@testable import Connectivity

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")
private let curl = ExerciseRef(catalogId: "curl", name: "Pregib")

private func plan() -> PlannedWorkoutPayload {
    PlannedWorkoutPayload(
        templateId: UUID(), scheduleId: UUID(), name: "Pull", scheduleName: "PPL", kind: .strength,
        exercises: [
            PlannedExercisePayload(exercise: row, inputType: .weightReps, restSeconds: 120, sets: [
                PlannedSetPayload(kind: .warmUp, weightKg: 40, reps: 10),
                PlannedSetPayload(weightKg: 60, reps: 8),
            ]),
            PlannedExercisePayload(exercise: curl, inputType: .weightReps, supersetGroup: 3, sets: [
                PlannedSetPayload(weightKg: 12, reps: 12), PlannedSetPayload(weightKg: 12, reps: 12),
            ]),
            PlannedExercisePayload(exercise: bench, inputType: .weightReps, restSeconds: 60, supersetGroup: 3, sets: [
                PlannedSetPayload(weightKg: 50, reps: 10), PlannedSetPayload(weightKg: 50, reps: 10),
            ]),
        ]
    )
}

@Suite("Trening na satu (SnapshotEngine)")
struct SnapshotEngineTests {

    @Test("Početak iz plana: novi UUID-ovi, isti redoslijed, vrijednosti i superset")
    func start() {
        let payload = plan()
        let snapshot = SnapshotEngine.start(payload, device: .watch, now: base)
        #expect(snapshot.name == "Pull")
        #expect(snapshot.templateId == payload.templateId)
        #expect(snapshot.scheduleId == payload.scheduleId)
        #expect(snapshot.controllingDevice == .watch)
        #expect(snapshot.state == .active)
        #expect(snapshot.visibleExercises.map(\.exercise) == [row, curl, bench])
        #expect(snapshot.exercises[0].orderedSets.map(\.kind) == [.warmUp, .working])
        #expect(snapshot.exercises[0].orderedSets.map(\.weightKg) == [40, 60])
        #expect(snapshot.exercises[0].supersetGroupId == nil)
        #expect(snapshot.exercises[1].supersetGroupId != nil)
        #expect(snapshot.exercises[1].supersetGroupId == snapshot.exercises[2].supersetGroupId)
        let ids = snapshot.exercises.flatMap { $0.sets.map(\.id) } + snapshot.exercises.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Kvačica pokreće pauzu vježbe, a nepotpuna serija se ne može označiti")
    func completeAndRest() throws {
        var engine = SnapshotEngine(snapshot: SnapshotEngine.start(plan(), device: .watch, now: base))
        let set = engine.snapshot.exercises[0].orderedSets[1]
        let timer = try engine.completeSet(set.id, defaultRestSeconds: 90, now: base.addingTimeInterval(60))
        #expect(timer?.totalSeconds == 120)
        #expect(engine.snapshot.restTimerEndsAt == base.addingTimeInterval(180))
        #expect(engine.snapshot.set(withID: set.id)?.completedAt == base.addingTimeInterval(60))
        #expect(engine.snapshot.updatedAt == base.addingTimeInterval(60))

        engine.adjustRest(bySeconds: 10, now: base.addingTimeInterval(70))
        #expect(engine.snapshot.restTimerEndsAt == base.addingTimeInterval(190))
        engine.cancelRest(now: base.addingTimeInterval(80))
        #expect(engine.restTimer == nil)

        let empty = engine.snapshot.exercises[0].orderedSets[0].id
        engine.updateSet(empty, now: base) { $0.reps = nil }
        var copy = engine
        #expect(throws: WorkoutError.setIncomplete) {
            try copy.completeSet(empty, defaultRestSeconds: 90, now: base)
        }

        engine.uncompleteSet(set.id, now: base.addingTimeInterval(90))
        #expect(engine.snapshot.set(withID: set.id)?.isCompleted == false)
    }

    @Test("Superset: bez pauze nakon prve vježbe, naizmjenične serije, zatim sljedeća vježba")
    func superset() throws {
        var engine = SnapshotEngine(snapshot: SnapshotEngine.start(plan(), device: .watch, now: base))
        let curlEx = engine.snapshot.exercises[1]
        let benchEx = engine.snapshot.exercises[2]

        #expect(engine.nextSet(forExercise: curlEx.id)?.set.id == curlEx.orderedSets[0].id)
        let afterCurl = try engine.completeSet(curlEx.orderedSets[0].id, defaultRestSeconds: 90, now: base)
        #expect(afterCurl == nil)
        #expect(engine.nextSet(forExercise: curlEx.id)?.set.id == benchEx.orderedSets[0].id)
        let afterBench = try engine.completeSet(benchEx.orderedSets[0].id, defaultRestSeconds: 90, now: base)
        #expect(afterBench?.totalSeconds == 60)
        #expect(engine.nextSet(forExercise: benchEx.id)?.set.id == curlEx.orderedSets[1].id)

        try engine.completeSet(curlEx.orderedSets[1].id, defaultRestSeconds: 90, now: base)
        try engine.completeSet(benchEx.orderedSets[1].id, defaultRestSeconds: 90, now: base)
        // Superset je gotov: sljedeća je prva nekompletirana vježba (veslanje).
        #expect(engine.exerciseAfterCompleting(in: curlEx.id) == engine.snapshot.exercises[0].id)
    }

    @Test("Nova serija preuzima vrijednosti zadnje serije iste vrste")
    func addSet() throws {
        var engine = SnapshotEngine(snapshot: SnapshotEngine.start(plan(), device: .watch, now: base))
        let exercise = engine.snapshot.exercises[0]
        engine.updateSet(exercise.orderedSets[1].id, now: base) { $0.rpe = 8 }
        let addedID = engine.addSet(to: exercise.id, now: base.addingTimeInterval(5))
        let added = try #require(addedID)
        let set = try #require(engine.snapshot.set(withID: added))
        #expect(set.orderIndex == 2)
        #expect(set.kind == .working)
        #expect(set.weightKg == 60)
        #expect(set.reps == 8)
        #expect(set.rpe == nil)
        #expect(!set.isCompleted)
    }

    @Test("Završetak briše nezavršene serije i prazne vježbe, bez serija se ne može završiti")
    func finish() throws {
        var engine = SnapshotEngine(snapshot: SnapshotEngine.start(plan(), device: .watch, now: base))
        var empty = engine
        #expect(throws: WorkoutError.nothingCompleted) { try empty.finish(now: base) }

        let set = engine.snapshot.exercises[0].orderedSets[1]
        try engine.completeSet(set.id, defaultRestSeconds: 90, now: base.addingTimeInterval(60))
        try engine.finish(now: base.addingTimeInterval(1800))
        #expect(engine.snapshot.state == .finished)
        #expect(engine.snapshot.endedAt == base.addingTimeInterval(1800))
        #expect(engine.snapshot.restTimerEndsAt == nil)
        #expect(engine.snapshot.exercises.count == 1)
        #expect(engine.snapshot.exercises[0].sets.map(\.id) == [set.id])
        #expect(engine.snapshot.completedSetCount == 1)
        #expect(engine.totalVolumeKg == 480)
    }

    @Test("Razlika dviju snimki kao naredbe daje istu snimku")
    func diffAndApply() throws {
        let start = SnapshotEngine.start(plan(), device: .watch, now: base)
        var engine = SnapshotEngine(snapshot: start)
        let row = start.exercises[0]
        try engine.completeSet(row.orderedSets[0].id, defaultRestSeconds: 90, now: base.addingTimeInterval(10))
        engine.updateSet(row.orderedSets[1].id, now: base.addingTimeInterval(20)) { $0.weightKg = 62.5 }
        engine.addSet(to: row.id, kind: .working, now: base.addingTimeInterval(30))

        var edited = engine.snapshot
        edited.exercises[1].isRemoved = true
        edited.exercises[2].sets.removeAll { $0.orderIndex == 1 }
        edited.exercises.append(ExerciseSnapshot(orderIndex: 3, exercise: bench, inputType: .bodyweight,
                                                 sets: [SetSnapshot(orderIndex: 0, reps: 15)]))
        edited.notes = "Dobar dan"

        let commands = SnapshotDiff.commands(from: start, to: edited)
        let applied = SnapshotDiff.apply(commands, to: start, at: base.addingTimeInterval(40))
        var expected = edited
        expected.updatedAt = base.addingTimeInterval(40)
        #expect(normalized(applied) == normalized(expected))
        #expect(SnapshotDiff.commands(from: edited, to: edited).isEmpty)
    }

    @Test("Završetak i odbacivanje putuju kao naredbe")
    func finishCommand() throws {
        let start = SnapshotEngine.start(plan(), device: .watch, now: base)
        var engine = SnapshotEngine(snapshot: start)
        try engine.completeSet(start.exercises[0].orderedSets[1].id, defaultRestSeconds: 90, now: base)
        let completed = engine.snapshot
        try engine.finish(now: base.addingTimeInterval(600))

        let commands = SnapshotDiff.commands(from: completed, to: engine.snapshot)
        #expect(commands.last == .finish(at: base.addingTimeInterval(600)))
        let applied = SnapshotDiff.apply(commands, to: completed, at: base.addingTimeInterval(601))
        #expect(applied.state == .finished)
        #expect(applied.completedSetCount == 1)

        // Završetak bez ijedne završene serije ne zatvara trening.
        let ignored = SnapshotDiff.apply([.finish(at: base)], to: start, at: base)
        #expect(ignored.state == .active)

        let discarded = SnapshotDiff.apply([.discard], to: start, at: base)
        #expect(discarded.state == .discarded)
    }

    @Test("Naredba za nepostojeću seriju se preskače, a stara vježba zadržava svoje serije")
    func applyRobustness() {
        let start = SnapshotEngine.start(plan(), device: .watch, now: base)
        var changed = start.exercises[0]
        changed.restSeconds = 30
        changed.sets = []
        let applied = SnapshotDiff.apply([
            .upsertSet(exerciseID: UUID(), set: SetSnapshot(orderIndex: 0)),
            .upsertExercise(changed),
        ], to: start, at: base.addingTimeInterval(1))
        #expect(applied.exercises[0].restSeconds == 30)
        #expect(applied.exercises[0].sets == start.exercises[0].sets)
        #expect(applied.updatedAt == base.addingTimeInterval(1))
    }

    /// Redoslijed u poljima nije bitan (vrijedi `orderIndex`).
    private func normalized(_ snapshot: SessionSnapshot) -> SessionSnapshot {
        var copy = snapshot
        copy.exercises = copy.orderedExercises.map { exercise in
            var sorted = exercise
            sorted.sets = exercise.orderedSets
            return sorted
        }
        return copy
    }
}

@Suite("Polja serije na satu")
struct WatchSetFieldTests {

    @Test("Polja prema vrsti unosa")
    func fields() {
        #expect(WatchSetField.fields(for: .weightReps) == [.weight, .reps])
        #expect(WatchSetField.fields(for: .assisted) == [.extraWeight, .reps])
        #expect(WatchSetField.fields(for: .bodyweight) == [.reps])
        #expect(WatchSetField.fields(for: .durationDistance) == [.duration, .distance])
    }

    @Test("Težina se upisuje u kilogramima i zaokružuje na korak krune")
    func weightConversion() {
        var set = SetSnapshot(orderIndex: 0)
        WatchSetField.weight.apply(100.3, to: &set, unit: .pounds)
        #expect(abs((set.weightKg ?? 0) - 100 * WeightConversion.kilogramsPerPound) < 1e-9)
        #expect(WatchSetField.weight.value(in: set, unit: .pounds) == 100)
        #expect(WatchSetField.weight.text(in: set, unit: .pounds, locale: Locale(identifier: "hr_HR")) == "100")

        WatchSetField.weight.apply(81.1, to: &set, unit: .kilograms)
        #expect(set.weightKg == 81.25)
        #expect(WatchSetField.weight.text(in: set, unit: .kilograms, locale: Locale(identifier: "hr_HR")) == "81,25")

        WatchSetField.reps.apply(-3, to: &set, unit: .kilograms)
        #expect(set.reps == 0)
    }

    @Test("Ista vrijednost ne bilježi promjenu, a prazno polje se popunjava i nulom")
    func matches() {
        let set = SetSnapshot(orderIndex: 0, weightKg: 80, reps: 8, durationSeconds: 95)
        #expect(WatchSetField.weight.matches(80, in: set, unit: .kilograms))
        #expect(!WatchSetField.weight.matches(81.25, in: set, unit: .kilograms))
        #expect(WatchSetField.reps.matches(8, in: set, unit: .kilograms))
        #expect(!WatchSetField.distance.matches(0, in: set, unit: .kilograms))
        #expect(WatchSetField.duration.text(in: set, unit: .kilograms) == "1:35")
    }
}

@Suite("Vrijednosti serije u Live Activityju")
struct LiveSetEditorTests {
    private let hr = Locale(identifier: "hr_HR")

    /// Prva serija nove vježbe. Vraća i engine, da baza živi do kraja testa.
    private func makeSet(_ inputType: ExerciseInputType = .weightReps) throws -> (WorkoutEngine, SetLog) {
        let engine = WorkoutEngine(context: ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory)))
        let session = try engine.startSession(name: "A", now: base)
        let exercise = try engine.addExercise(bench, inputType: inputType, to: session, now: base)
        return (engine, try #require(exercise.orderedSets.first))
    }

    @Test("Težina i ponavljanja s jedinicom, prazno polje kao crtica")
    func values() throws {
        let (engine, set) = try makeSet()
        defer { withExtendedLifetime(engine) {} }
        set.weightKg = 82.5
        set.reps = nil

        let values = LiveSetEditor.values(of: set, inputType: .weightReps, unit: .kilograms, locale: hr)
        #expect(values.map(\.field) == [.weight, .reps])
        #expect(values[0].text == "82,5")
        #expect(values[0].unitSymbol == "kg")
        #expect(values[0].canDecrease && values[0].canIncrease)
        #expect(values[1].text == "–")
        #expect(values[1].unitSymbol.isEmpty)
        // Prazno polje se ne smanjuje, a + ga popunjava.
        #expect(!values[1].canDecrease)
        #expect(values[1].canIncrease)
    }

    @Test("Plus i minus mijenjaju za jedan korak krune, težina ostaje u kilogramima")
    func adjust() throws {
        let (engine, set) = try makeSet()
        defer { withExtendedLifetime(engine) {} }
        set.weightKg = 80
        set.reps = 8

        #expect(LiveSetEditor.adjust(set, field: .weight, steps: 1, unit: .kilograms))
        #expect(set.weightKg == 81.25)
        #expect(LiveSetEditor.adjust(set, field: .reps, steps: -1, unit: .kilograms))
        #expect(set.reps == 7)
        #expect(set.weightKg == 81.25)

        // U funtama je korak 2,5 lbs, a sprema se u kilogramima.
        set.weightKg = 100 * WeightConversion.kilogramsPerPound
        #expect(LiveSetEditor.adjust(set, field: .weight, steps: 1, unit: .pounds))
        #expect(abs((set.weightKg ?? 0) - 102.5 * WeightConversion.kilogramsPerPound) < 1e-9)
    }

    @Test("Na rubu raspona i u praznom polju minus ne mijenja ništa")
    func bounds() throws {
        let (engine, set) = try makeSet()
        defer { withExtendedLifetime(engine) {} }
        set.reps = 0
        #expect(!LiveSetEditor.adjust(set, field: .reps, steps: -1, unit: .kilograms))
        #expect(set.reps == 0)

        set.weightKg = nil
        #expect(!LiveSetEditor.adjust(set, field: .weight, steps: -1, unit: .kilograms))
        #expect(set.weightKg == nil)
        #expect(LiveSetEditor.adjust(set, field: .weight, steps: 1, unit: .kilograms))
        #expect(set.weightKg == 1.25)
    }

    @Test("Trajanje i udaljenost")
    func cardio() throws {
        let (engine, set) = try makeSet(.durationDistance)
        defer { withExtendedLifetime(engine) {} }
        set.durationSeconds = 90
        set.distanceMeters = 400

        let values = LiveSetEditor.values(of: set, inputType: .durationDistance, unit: .kilograms, locale: hr)
        #expect(values.map(\.text) == ["1:30", "400"])
        #expect(values.map(\.unitSymbol) == ["", "m"])

        #expect(LiveSetEditor.adjust(set, field: .duration, steps: 1, unit: .kilograms))
        #expect(set.durationSeconds == 95)
        #expect(LiveSetEditor.adjust(set, field: .distance, steps: -1, unit: .kilograms))
        #expect(set.distanceMeters == 350)
    }
}
