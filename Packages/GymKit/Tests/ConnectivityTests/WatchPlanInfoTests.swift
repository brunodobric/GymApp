import Catalog
import Foundation
import Models
import Testing
import Training
@testable import Connectivity

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let bike = ExerciseRef(catalogId: "bike", name: "Sobni bicikl")

private func plan(cardio: Bool = true) -> PlannedWorkoutPayload {
    var exercises = [
        PlannedExercisePayload(
            exercise: bench, inputType: .weightReps, restSeconds: 120,
            sets: [
                PlannedSetPayload(kind: .warmUp, weightKg: 40, reps: 10),
                PlannedSetPayload(weightKg: 80, reps: 8),
                PlannedSetPayload(weightKg: 80, reps: 8)
            ],
            isCardio: false,
            previous: [
                PlannedSetPayload(kind: .warmUp, weightKg: 40, reps: 10),
                PlannedSetPayload(weightKg: 77.5, reps: 8),
                PlannedSetPayload(weightKg: 80, reps: 7)
            ]
        )
    ]
    if cardio {
        exercises.append(PlannedExercisePayload(
            exercise: bike, inputType: .durationDistance,
            sets: [PlannedSetPayload(durationSeconds: 900)], isCardio: true
        ))
    }
    return PlannedWorkoutPayload(
        templateId: UUID(), scheduleId: nil, name: "Push", scheduleName: nil, kind: .strength, exercises: exercises
    )
}

private func context(_ plans: [PlannedWorkoutPayload]) -> WatchContextPayload {
    WatchContextPayload(
        upcoming: plans, templates: [], weightUnit: .kilograms, defaultRestSeconds: 90, savesToHealth: false,
        generatedAt: base
    )
}

@Suite("Podaci za prikaz na satu")
struct WatchPlanInfoTests {

    @Test("Vrsta treninga iz vježbi: snaga, kardio ili oboje")
    func mix() {
        #expect(plan().mix == .mixed)
        #expect(plan(cardio: false).mix == .strength)
        #expect(SessionMix.from(cardioFlags: [true, true]) == .cardio)
        #expect(SessionMix.from(cardioFlags: []) == .strength)
        // Kontekst iz starije aplikacije nema oznaku: vježba se smatra snagom.
        var old = plan()
        for index in old.exercises.indices { old.exercises[index].isCardio = nil }
        #expect(old.mix == .strength)
    }

    @Test("Procjena trajanja: rad, odmor između serija i prijelaz, zaokruženo na 5 minuta")
    func estimate() {
        // Snaga: 3 × 45 s + 2 × 120 s = 375 s; prijelaz 60 s; bicikl 900 s. Ukupno 1335 s ≈ 22 min → 20.
        #expect(plan().estimatedMinutes(defaultRestSeconds: 90) == 20)
        // Samo snaga: 375 s, ali najmanje 5 minuta.
        #expect(plan(cardio: false).estimatedMinutes(defaultRestSeconds: 90) == 5)
        let empty = PlannedWorkoutPayload(templateId: nil, scheduleId: nil, name: "", scheduleName: nil, kind: .strength, exercises: [])
        #expect(empty.estimatedMinutes(defaultRestSeconds: 90) == nil)
    }

    @Test("Prošli put: serija iste vrste na istom mjestu, a iznad broja prošlih zadnja")
    func previous() {
        let payload = context([plan()])
        #expect(payload.previousSet(for: bench, kind: .working, position: 0)?.weightKg == 77.5)
        #expect(payload.previousSet(for: bench, kind: .working, position: 1)?.reps == 7)
        #expect(payload.previousSet(for: bench, kind: .working, position: 5)?.weightKg == 80)
        #expect(payload.previousSet(for: bench, kind: .warmUp, position: 0)?.weightKg == 40)
        #expect(payload.previousSet(for: bike, kind: .working, position: 0) == nil)
    }

    @Test("Kardio vježba se prepoznaje po ključu, nepoznata nije kardio")
    func cardioLookup() {
        let payload = context([plan()])
        #expect(payload.isCardio(bike))
        #expect(!payload.isCardio(bench))
        #expect(!payload.isCardio(ExerciseRef(catalogId: "row", name: "Veslanje")))
    }

    @Test("Broj serije: radne 1, 2…, zagrijavanje bez broja")
    func setNumbers() {
        let snapshot = SnapshotEngine.start(plan(), device: .watch, now: base)
        let exercise = snapshot.visibleExercises[0]
        let sets = exercise.orderedSets
        #expect(exercise.workingNumber(ofSet: sets[0].id) == nil)
        #expect(exercise.position(ofSet: sets[0].id) == 0)
        #expect(exercise.workingNumber(ofSet: sets[1].id) == 1)
        #expect(exercise.workingNumber(ofSet: sets[2].id) == 2)
        #expect(exercise.position(ofSet: sets[2].id) == 1)
    }

    @Test("Sažetak: kardio dio, vrsta i serije bez kardija")
    func summary() throws {
        var engine = SnapshotEngine(snapshot: SnapshotEngine.start(plan(), device: .watch, now: base))
        let isCardio: (ExerciseRef) -> Bool = { $0 == bike }
        let benchSets = engine.snapshot.visibleExercises[0].orderedSets
        _ = try engine.completeSet(benchSets[1].id, defaultRestSeconds: 90, now: base.addingTimeInterval(60))
        #expect(engine.snapshot.mix(isCardio: isCardio) == .strength)
        #expect(engine.snapshot.cardioPart(isCardio: isCardio) == nil)

        let bikeSet = engine.snapshot.visibleExercises[1].orderedSets[0]
        engine.updateSet(bikeSet.id) { $0.distanceMeters = 5_000 }
        _ = try engine.completeSet(bikeSet.id, defaultRestSeconds: 90, now: base.addingTimeInterval(1_200))
        #expect(engine.snapshot.mix(isCardio: isCardio) == .mixed)
        #expect(engine.snapshot.cardioPart(isCardio: isCardio) == CardioPart(seconds: 900, meters: 5_000))
        #expect(engine.snapshot.strengthSetCount(isCardio: isCardio) == 1)
        #expect(engine.snapshot.completedExerciseCount == 1)
    }
}
