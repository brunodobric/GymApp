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

@Suite("Zadana pauza prema vrsti vježbe (WorkoutEngine)")
struct RestByMechanicTests {

    @Test("Vježba bez vlastite pauze dobiva zadanu prema vrsti, a vlastita pauza ima prednost")
    func restByMechanic() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let compound = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let isolation = try engine.addExercise(row, inputType: .weightReps, to: session, now: base)
        let own = try engine.addExercise(bench, inputType: .weightReps, to: session, restSeconds: 60, now: base)
        for set in [compound.orderedSets[0], isolation.orderedSets[0], own.orderedSets[0]] {
            set.weightKg = 50
            set.reps = 10
        }
        let defaults = RestDefaults(compoundSeconds: 180, otherSeconds: 75)
        let isCompound: (String) -> Bool? = { $0 == bench.key ? true : nil }
        #expect(try engine.completeSet(
            compound.orderedSets[0], restDefaults: defaults, isCompound: isCompound, now: base
        )?.totalSeconds == 180)
        #expect(try engine.completeSet(
            isolation.orderedSets[0], restDefaults: defaults, isCompound: isCompound, now: base
        )?.totalSeconds == 75)
        #expect(try engine.completeSet(
            own.orderedSets[0], restDefaults: defaults, isCompound: isCompound, now: base
        )?.totalSeconds == 60)
    }

    @Test("Superset sa složenom vježbom odmara kao složena vježba")
    func supersetRestByMechanic() throws {
        let (engine, _) = try makeEngine()
        let session = try engine.startSession(name: "A", now: base)
        let first = try engine.addExercise(bench, inputType: .weightReps, to: session, now: base)
        let second = try engine.addExercise(row, inputType: .weightReps, to: session, now: base)
        try engine.makeSuperset([first, second], in: session, now: base)
        for set in [first.orderedSets[0], second.orderedSets[0]] {
            set.weightKg = 50
            set.reps = 10
        }
        let defaults = RestDefaults(compoundSeconds: 150, otherSeconds: 90)
        let isCompound: (String) -> Bool? = { $0 == bench.key }
        #expect(try engine.completeSet(
            first.orderedSets[0], restDefaults: defaults, isCompound: isCompound, now: base
        ) == nil)
        #expect(try engine.completeSet(
            second.orderedSets[0], restDefaults: defaults, isCompound: isCompound, now: base
        )?.totalSeconds == 150)
    }
}
