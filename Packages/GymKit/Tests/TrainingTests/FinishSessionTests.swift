import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Training

@Suite("Završetak treninga")
struct FinishSessionTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Udaljenost izbačene vježbe ne ulazi u udaljenost treninga")
    func removedExerciseDistance() throws {
        let context = ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
        let engine = WorkoutEngine(context: context)
        let session = try engine.startSession(name: "Kardio", now: base)
        let run = try engine.addExercise(ExerciseRef(catalogId: "run", name: "Trčanje"), inputType: .durationDistance, to: session, now: base)
        let bike = try engine.addExercise(ExerciseRef(catalogId: "bike", name: "Bicikl"), inputType: .durationDistance, to: session, now: base)
        for (exercise, meters) in [(run, 3000.0), (bike, 8000.0)] {
            let set = try #require(exercise.orderedSets.first)
            set.durationSeconds = 900
            set.distanceMeters = meters
            try engine.completeSet(set, defaultRestSeconds: 60, now: base.addingTimeInterval(900))
        }
        try engine.removeExercise(bike, now: base)
        try engine.finishSession(session, now: base.addingTimeInterval(2000))
        #expect(session.distanceMeters == 3000)
    }
}
