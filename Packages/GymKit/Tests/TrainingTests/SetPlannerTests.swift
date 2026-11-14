import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Training
import Units

private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let press = ExerciseRef(catalogId: "press", name: "Potisak bučicama")
private let fly = ExerciseRef(catalogId: "fly", name: "Razvlačenje")
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func working(_ weight: Double?, _ reps: Int?) -> SetValues {
    SetValues(kind: .working, weightKg: weight, reps: reps)
}

private func range(_ count: Int, _ lower: Int, _ upper: Int) -> [SetTarget] {
    Array(repeating: SetTarget(kind: .working, reps: lower, repsMax: upper), count: count)
}

@Suite("Plan serija i dvostruka progresija")
struct SetPlannerTests {

    @Test("Raspon ponavljanja zadržava prošla ponavljanja unutar granica")
    func keepsRepsInRange() {
        let previous = [working(80, 10), working(80, 13), working(80, 6)]
        let plan = SetPlanner.plan(previous: previous, targets: range(3, 8, 12), inputType: .weightReps, weightStep: 2.5)
        #expect(plan.sets.map(\.reps) == [10, 12, 8])
        #expect(plan.sets.map(\.weightKg) == [80, 80, 80])
        #expect(plan.loadChangeKg == nil)
        #expect(plan.repRange == RepRange(lower: 8, upper: 12))
    }

    @Test("Bez povijesti raspon počinje od donje granice")
    func startsAtLowerBound() {
        let plan = SetPlanner.plan(previous: [], targets: range(3, 8, 12), inputType: .weightReps, weightStep: 2.5)
        #expect(plan.sets.map(\.reps) == [8, 8, 8])
        #expect(plan.loadChangeKg == nil)
    }

    @Test("Gornja granica u svim serijama podiže težinu za korak i vraća ponavljanja na donju granicu")
    func increasesLoad() {
        let previous = [working(80, 12), working(80, 12), working(77.5, 13)]
        let plan = SetPlanner.plan(previous: previous, targets: range(3, 8, 12), inputType: .weightReps, weightStep: 2.5)
        #expect(plan.sets.map(\.weightKg) == [82.5, 82.5, 80])
        #expect(plan.sets.map(\.reps) == [8, 8, 8])
        #expect(plan.loadChangeKg == 2.5)
    }

    @Test("Jedna serija ispod gornje granice ili manje serija ne podiže težinu")
    func noIncreaseWhenShort() {
        let previous = [working(80, 12), working(80, 11), working(80, 12)]
        #expect(!SetPlanner.shouldIncreaseLoad(targets: range(3, 8, 12), previous: previous, inputType: .weightReps))
        #expect(!SetPlanner.shouldIncreaseLoad(targets: range(3, 8, 12), previous: Array(previous.prefix(2)), inputType: .weightReps))
    }

    @Test("Propisana težina u predlošku isključuje prijedlog")
    func fixedWeightWins() {
        let targets = [SetTarget(kind: .working, weightKg: 80, reps: 8, repsMax: 12)]
        let plan = SetPlanner.plan(previous: [working(80, 12)], targets: targets, inputType: .weightReps, weightStep: 2.5)
        #expect(plan.sets[0].weightKg == 80)
        #expect(plan.loadChangeKg == nil)
    }

    @Test("Fiksni cilj radi kao raspon s istim granicama")
    func fixedTarget() {
        let previous = Array(repeating: working(100, 5), count: 5)
        let targets = Array(repeating: SetTarget(kind: .working, reps: 5), count: 5)
        let plan = SetPlanner.plan(previous: previous, targets: targets, inputType: .weightReps, weightStep: 2.5)
        #expect(plan.sets[0].weightKg == 102.5)
        #expect(plan.repRange == RepRange(lower: 5, upper: 5))
    }

    @Test("Korak je u jedinici prikaza i težina izvan koraka ide na sljedeću")
    func steps() {
        #expect(SetPlanner.stepped(83, by: 1, step: 2.5, unit: .kilograms) == 85)
        #expect(SetPlanner.stepped(83, by: -1, step: 2.5, unit: .kilograms) == 82.5)
        let pounds = SetPlanner.stepped(100 * 0.45359237, by: 1, step: 5, unit: .pounds)
        #expect(abs(pounds - 105 * 0.45359237) < 1e-9)
    }

    @Test("Potpomognuta vježba smanjuje pomoć, a dodatni teret raste i od nule")
    func assistedAndWeighted() {
        let assisted = SetPlanner.plan(
            previous: [SetValues(kind: .working, reps: 10, extraWeightKg: 20)], targets: range(1, 6, 10),
            inputType: .assisted, weightStep: 5
        )
        #expect(assisted.sets[0].extraWeightKg == 15)
        #expect(assisted.loadChangeKg == -5)

        let weighted = SetPlanner.plan(
            previous: [SetValues(kind: .working, reps: 10)], targets: range(1, 6, 10),
            inputType: .weightedBodyweight, weightStep: 2.5
        )
        #expect(weighted.sets[0].extraWeightKg == 2.5)
        #expect(weighted.sets[0].reps == 6)
    }

    @Test("Vlastita težina i plan bez koraka nemaju prijedlog težine")
    func noStepNoIncrease() {
        let bodyweight = SetPlanner.plan(
            previous: [SetValues(kind: .working, reps: 15)], targets: range(1, 8, 12), inputType: .bodyweight, weightStep: 2.5
        )
        #expect(bodyweight.sets[0].reps == 12)
        #expect(bodyweight.loadChangeKg == nil)
        #expect(SetPlanner.plan(previous: [working(80, 12)], targets: range(1, 8, 12), inputType: .weightReps).loadChangeKg == nil)
    }

    @Test("Zagrijavanje: prazna šipka, 40, 60 i 80 % zaokruženo na korak, bez ponavljanja težine")
    func warmUpRamp() {
        let sets = WarmUpGenerator.sets(workingWeightKg: 100, barKg: 20, step: 2.5, unit: .kilograms)
        #expect(sets.map(\.weightKg) == [20, 40, 60, 80])
        #expect(sets.map(\.reps) == [10, 5, 3, 1])
        #expect(sets.allSatisfy { $0.kind == .warmUp })
        // Lagana radna težina: 40 % je ispod šipke, a 60 % i 80 % padaju na istu težinu.
        let light = WarmUpGenerator.sets(workingWeightKg: 30, barKg: 20, step: 5, unit: .kilograms)
        #expect(light.map(\.weightKg) == [20, 25])
        // Bez šipke (bučice) nema prve serije.
        #expect(WarmUpGenerator.sets(workingWeightKg: 30, barKg: nil, step: 2, unit: .kilograms).map(\.weightKg) == [12, 18, 24])
        #expect(WarmUpGenerator.sets(workingWeightKg: 0, barKg: 20, step: 2.5, unit: .kilograms).isEmpty)
    }

    @Test("Oznaka rekorda dok trening traje: samo serija koja sama obara rekord")
    func liveRecords() {
        let history = RecordHistory(sessions: Array(repeating: [working(100, 5)], count: 3), inputType: .weightReps)
        let strong = UUID()
        let same = UUID()
        let warmUp = UUID()
        let marked = PersonalRecordDetector.liveRecordSets(
            [(strong, working(110, 5)), (same, working(100, 5)), (warmUp, SetValues(kind: .warmUp, weightKg: 120, reps: 5))],
            history: history, inputType: .weightReps, kinds: Set(PRKind.allCases)
        )
        #expect(marked == [strong])
        // Premalo ranijih izvođenja (kalibracija) ili isključeni rekordi: bez oznake.
        let young = RecordHistory(sessions: [[working(100, 5)]], inputType: .weightReps)
        #expect(PersonalRecordDetector.liveRecordSets([(strong, working(110, 5))], history: young, inputType: .weightReps, kinds: Set(PRKind.allCases)).isEmpty)
        #expect(PersonalRecordDetector.liveRecordSets([(strong, working(110, 5))], history: history, inputType: .weightReps, kinds: []).isEmpty)
    }

    @Test("Broj radnih serija je najčešći iz zadnjih izvođenja")
    func workingSetCount() {
        #expect(SmartDefaults.workingSetCount(recent: [2, 4, 4]) == 4)
        #expect(SmartDefaults.workingSetCount(recent: [2, 4]) == 2)
        #expect(SmartDefaults.workingSetCount(recent: []) == nil)
        let plan = SetPlanner.plan(previous: [working(60, 8), working(60, 8)], recentWorkingCounts: [2, 4, 4], inputType: .weightReps)
        #expect(plan.sets.count == 4)
        #expect(plan.sets.map(\.weightKg) == [60, 60, 60, 60])
    }
}

@Suite("Plan serija u treningu")
struct SetPlannerEngineTests {

    private func makeEngine() throws -> (WorkoutEngine, ModelContext) {
        let context = ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
        return (WorkoutEngine(context: context), context)
    }

    private func finished(
        _ engine: WorkoutEngine, at start: Date, sets: [(Double, Int)], templateId: UUID? = nil, ref: ExerciseRef = bench
    ) throws {
        let session = try engine.startSession(name: "Trening", templateId: templateId, now: start)
        let exercise = try engine.addExercise(ref, inputType: .weightReps, to: session, now: start)
        for set in exercise.orderedSets { try engine.removeSet(set, now: start) }
        for values in sets {
            let set = try engine.addSet(to: exercise, now: start)
            set.weightKg = values.0
            set.reps = values.1
            try engine.completeSet(set, defaultRestSeconds: 90, now: start.addingTimeInterval(60))
        }
        try engine.finishSession(session, now: start.addingTimeInterval(3600))
    }

    @Test("Prošli put dolazi iz istog treninga kad postoji")
    func sameTemplateFirst() throws {
        let (engine, context) = try makeEngine()
        let heavy = UUID()
        let light = UUID()
        try finished(engine, at: base, sets: [(140, 5)], templateId: heavy)
        try finished(engine, at: base + 86_400, sets: [(100, 12)], templateId: light)

        let queries = GymQueries(context: context)
        #expect(try queries.previousSetValues(of: bench, preferringTemplate: heavy).map(\.weightKg) == [140])
        #expect(try queries.previousSetValues(of: bench).map(\.weightKg) == [100])
        let session = try engine.startSession(name: "Teško", templateId: heavy, now: base + 2 * 86_400)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base + 2 * 86_400)
        #expect(exercise.orderedSets.first?.weightKg == 140)
    }

    @Test("Jedan prekinut trening ne smanjuje broj serija")
    func interruptedWorkout() throws {
        let (engine, _) = try makeEngine()
        try finished(engine, at: base, sets: Array(repeating: (60, 8), count: 4))
        try finished(engine, at: base + 86_400, sets: Array(repeating: (60, 8), count: 4))
        try finished(engine, at: base + 2 * 86_400, sets: Array(repeating: (62.5, 8), count: 2))
        let session = try engine.startSession(name: "Novi", now: base + 3 * 86_400)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base + 3 * 86_400)
        #expect(exercise.orderedSets.count == 4)
        #expect(exercise.orderedSets.first?.weightKg == 62.5)
    }

    @Test("Zamjena bez završenih serija mijenja vježbu na istom mjestu")
    func replaceInPlace() throws {
        let (engine, _) = try makeEngine()
        try finished(engine, at: base, sets: [(30, 10), (30, 10)], ref: press)
        let session = try engine.startSession(name: "Push", now: base + 86_400)
        let first = try engine.addExercise(bench, inputType: .weightReps, to: session)
        let second = try engine.addExercise(fly, inputType: .weightReps, to: session)
        first.supersetGroupId = UUID()
        let group = first.supersetGroupId

        let created = try engine.replaceExercise(first, with: press, inputType: .weightReps)
        let visible = engine.visibleExercises(in: session)
        #expect(visible.map(\.exerciseKey) == [press.key, second.exerciseKey])
        #expect(created.orderedSets.count == 3)
        #expect(created.orderedSets.first?.weightKg == 30)
        #expect(created.supersetGroupId == group)
    }

    @Test("Zamjena nakon završenih serija ostavlja odrađeno i dodaje preostale serije iza")
    func replaceAfterProgress() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "Push", now: base)
        let first = try engine.addExercise(bench, inputType: .weightReps, to: session)
        try engine.addExercise(fly, inputType: .weightReps, to: session)
        let done = try #require(first.orderedSets.first)
        done.weightKg = 80
        done.reps = 8
        try engine.completeSet(done, defaultRestSeconds: 90, now: base)

        let created = try engine.replaceExercise(first, with: press, inputType: .weightReps)
        let visible = engine.visibleExercises(in: session)
        #expect(visible.map(\.exerciseKey) == [bench.key, press.key, fly.key])
        #expect(first.orderedSets.count == 1)
        let allCompleted = first.orderedSets.allSatisfy(\.isCompleted)
        #expect(allCompleted)
        #expect(created.orderedSets.count == 2)
    }

    @Test("Dodaj zagrijavanje stavlja serije ispred radnih, samo jednom")
    func addWarmUps() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "Push", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session)
        #expect(!engine.canAddWarmUps(to: exercise))
        for set in exercise.orderedSets {
            set.weightKg = 100
            set.reps = 5
        }
        #expect(try engine.addWarmUps(to: exercise, barKg: 20, step: 2.5, unit: .kilograms) == 4)
        #expect(exercise.orderedSets.map(\.kind) == [.warmUp, .warmUp, .warmUp, .warmUp, .working, .working, .working])
        #expect(exercise.orderedSets.map(\.orderIndex) == Array(0..<7))
        #expect(!engine.canAddWarmUps(to: exercise))
        #expect(try engine.addWarmUps(to: exercise, barKg: 20, step: 2.5, unit: .kilograms) == 0)
    }

    @Test("Nakon zagrijavanja odmor je kraći: 60 s, a pred radnu seriju pola pune pauze")
    func warmUpRest() throws {
        #expect(RestPolicy.afterWarmUp(fullSeconds: 150, nextIsWarmUp: true) == 60)
        #expect(RestPolicy.afterWarmUp(fullSeconds: 150, nextIsWarmUp: false) == 75)
        #expect(RestPolicy.afterWarmUp(fullSeconds: 90, nextIsWarmUp: false) == 60)
        #expect(RestPolicy.afterWarmUp(fullSeconds: 45, nextIsWarmUp: true) == 45)
        #expect(RestPolicy.afterWarmUp(fullSeconds: 0, nextIsWarmUp: false) == 0)

        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "Push", now: base)
        let exercise = try engine.addExercise(bench, inputType: .weightReps, to: session)
        for _ in 0..<2 { try engine.addSet(to: exercise, kind: .warmUp) }
        let warmUps = exercise.orderedSets.filter { $0.kind == .warmUp }
        try #require(warmUps.count == 2)
        let first = warmUps[0]
        let second = warmUps[1]
        for set in [first, second] {
            set.weightKg = 40
            set.reps = 5
        }
        #expect(try engine.completeSet(first, defaultRestSeconds: 180, now: base)?.totalSeconds == 60)
        #expect(try engine.completeSet(second, defaultRestSeconds: 180, now: base)?.totalSeconds == 90)
    }
}
