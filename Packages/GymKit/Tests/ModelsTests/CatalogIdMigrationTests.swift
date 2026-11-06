import Catalog
import Foundation
import SwiftData
import Testing
@testable import Models

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

/// Mali katalog: jedna nova vježba, stari id koji je preimenovan i stari id koji je izbačen.
private func makeCatalog() throws -> ExerciseCatalog {
    try ExerciseCatalog(data: Data("""
        {
          "version": 2,
          "source": {"name": "MoveKit", "url": "https://movekit.com", "license": "MoveKit License Agreement v1.0"},
          "legacyIds": {"Barbell_Squat": "barbell-squat", "Ab_Roller": null},
          "exercises": [{
            "id": "barbell-squat", "name": {"en": "Barbell Squat", "hr": "Čučanj sa šipkom"}, "category": "legs",
            "primaryMuscles": ["quadriceps"], "secondaryMuscles": [], "equipment": "barbell", "level": "beginner",
            "mechanic": "compound", "movement": "legs", "inputType": "weightReps",
            "primaryRegions": ["quads"], "secondaryRegions": []
          }]
        }
        """.utf8))
}

@Suite("Migracija id-jeva kataloga")
struct CatalogIdMigrationTests {

    @Test("Stari id u treningu dobiva novi id i ključ, naziv ostaje")
    func renamesSessionExercise() throws {
        let context = try makeContext()
        let session = Session(name: "Noge")
        context.insert(session)
        let exercise = SessionExercise(orderIndex: 0, exercise: ExerciseRef(catalogId: "Barbell_Squat", name: "Čučanj"))
        exercise.session = session
        try context.save()

        let result = try CatalogIdMigration.migrate(in: context, catalog: makeCatalog())
        #expect(result.renamed == 1)
        #expect(exercise.exerciseCatalogId == "barbell-squat")
        #expect(exercise.exerciseKey == "c:barbell-squat")
        #expect(exercise.exerciseName == "Čučanj")
    }

    @Test("Izbačena vježba postaje jedna vlastita vježba istog naziva")
    func removedBecomesCustom() throws {
        let context = try makeContext()
        let session = Session(name: "Trbuh")
        context.insert(session)
        let first = SessionExercise(orderIndex: 0, exercise: ExerciseRef(catalogId: "Ab_Roller", name: "Kotač za trbušnjake"), inputType: .bodyweight)
        first.session = session
        let template = WorkoutTemplate(name: "Trbuh")
        context.insert(template)
        let planned = TemplateExercise(orderIndex: 0, exercise: ExerciseRef(catalogId: "Ab_Roller", name: "kotač za trbušnjake"), inputType: .bodyweight)
        planned.template = template
        try context.save()

        let result = try CatalogIdMigration.migrate(in: context, catalog: makeCatalog())
        #expect(result.convertedToCustom == 2)
        #expect(result.createdCustomExercises == 1)
        let customs = try context.fetch(FetchDescriptor<CustomExercise>())
        #expect(customs.count == 1)
        let custom = try #require(customs.first)
        #expect(custom.name == "Kotač za trbušnjake")
        #expect(custom.inputType == .bodyweight)
        #expect(first.exerciseCatalogId == nil && first.exerciseCustomId == custom.id)
        #expect(first.exerciseKey == "u:\(custom.id.uuidString)")
        #expect(planned.exerciseCatalogId == nil && planned.exerciseCustomId == custom.id)
    }

    @Test("Postojeća vlastita vježba istog naziva se koristi")
    func reusesExistingCustom() throws {
        let context = try makeContext()
        let existing = CustomExercise(name: "Kotač za trbušnjake")
        context.insert(existing)
        let session = Session(name: "Trbuh")
        context.insert(session)
        let exercise = SessionExercise(orderIndex: 0, exercise: ExerciseRef(catalogId: "Ab_Roller", name: "Kotač za trbušnjake"))
        exercise.session = session
        try context.save()

        let result = try CatalogIdMigration.migrate(in: context, catalog: makeCatalog())
        #expect(result.createdCustomExercises == 0)
        #expect(exercise.exerciseCustomId == existing.id)
    }

    @Test("Izmjena ciklusa: zamjena i ciljna vježba dobivaju nove ključeve")
    func cycleOverride() throws {
        let context = try makeContext()
        let override = CycleOverride(scheduleId: UUID(), cycleNumber: 1, scheduleItemId: UUID(), kind: .replaceExercise)
        override.targetExerciseKey = "c:Barbell_Squat"
        override.replacement = ExerciseRef(catalogId: "Ab_Roller", name: "Kotač")
        override.replacementInputType = .bodyweight
        context.insert(override)
        try context.save()

        try CatalogIdMigration.migrate(in: context, catalog: makeCatalog())
        #expect(override.targetExerciseKey == "c:barbell-squat")
        #expect(override.replacementCatalogId == nil)
        let custom = try #require(try context.fetch(FetchDescriptor<CustomExercise>()).first)
        #expect(override.replacementCustomId == custom.id)
        #expect(custom.inputType == .bodyweight)
    }

    @Test("Nepoznati i ispravni id-jevi se ne diraju, a druga migracija ne mijenja ništa")
    func idempotent() throws {
        let context = try makeContext()
        let session = Session(name: "Mix")
        context.insert(session)
        for (index, id) in ["barbell-squat", "nepoznato", "Barbell_Squat"].enumerated() {
            let exercise = SessionExercise(orderIndex: index, exercise: ExerciseRef(catalogId: id, name: id))
            exercise.session = session
        }
        try context.save()

        let catalog = try makeCatalog()
        #expect(try CatalogIdMigration.migrate(in: context, catalog: catalog).renamed == 1)
        let ids = session.orderedExercises.map(\.exerciseCatalogId)
        #expect(ids == ["barbell-squat", "nepoznato", "barbell-squat"])
        #expect(try CatalogIdMigration.migrate(in: context, catalog: catalog) == CatalogIdMigration.Result())
    }
}
