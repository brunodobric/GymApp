import Catalog
import Foundation
import SwiftData
import Testing
import Units
@testable import Models

/// Katalog s jednom vježbom s bučicama i jednom na spravi.
private func makeCatalog() throws -> ExerciseCatalog {
    try ExerciseCatalog(data: Data("""
        {
          "version": 2,
          "source": {"name": "MoveKit", "url": "https://movekit.com", "license": "MoveKit License Agreement v1.0"},
          "exercises": [{
            "id": "dumbbell-curl", "name": {"en": "Dumbbell Curl", "hr": "Pregib s bučicama"}, "category": "arms",
            "primaryMuscles": ["biceps"], "secondaryMuscles": [], "equipment": "dumbbell", "level": "beginner",
            "mechanic": "isolation", "movement": "pull", "inputType": "weightReps",
            "primaryRegions": [], "secondaryRegions": []
          }, {
            "id": "leg-press", "name": {"en": "Leg Press", "hr": "Nožna preša"}, "category": "legs",
            "primaryMuscles": ["quadriceps"], "secondaryMuscles": [], "equipment": "machine", "level": "beginner",
            "mechanic": "compound", "movement": "legs", "inputType": "weightReps",
            "primaryRegions": [], "secondaryRegions": []
          }]
        }
        """.utf8))
}

@Suite("Korak težine po opremi i vježbi")
struct WeightStepsTests {

    @Test("Zadani koraci po opremi")
    func defaults() {
        let steps = WeightStepSettings()
        #expect(steps.step(for: .barbell, unit: .kilograms) == 2.5)
        #expect(steps.step(for: .ezBar, unit: .kilograms) == 2.5)
        #expect(steps.step(for: .dumbbell, unit: .kilograms) == 2)
        #expect(steps.step(for: .machine, unit: .kilograms) == 5)
        #expect(steps.step(for: .cable, unit: .kilograms) == 5)
        #expect(steps.step(for: .kettlebell, unit: .kilograms) == 4)
        #expect(steps.step(for: nil, unit: .kilograms) == 2.5)
        #expect(steps.step(for: .barbell, unit: .pounds) == 5)
        #expect(steps.step(for: .dumbbell, unit: .pounds) == 5)
        #expect(steps.step(for: .machine, unit: .pounds) == 10)
    }

    @Test("Zadani korak je uvijek među ponuđenima")
    func defaultsAreChoices() {
        for unit in WeightUnit.allCases {
            for equipment in Equipment.allCases {
                #expect(WeightStepSettings.choices(for: unit).contains(WeightStepSettings.defaultStep(for: equipment, unit: unit)))
            }
        }
    }

    @Test("Korak opreme vrijedi samo za svoju jedinicu, a zadani korak briše postavku")
    func equipmentStep() {
        var steps = WeightStepSettings()
        steps.setStep(2.5, for: .dumbbell, unit: .kilograms)
        #expect(steps.step(for: .dumbbell, unit: .kilograms) == 2.5)
        #expect(steps.step(for: .dumbbell, unit: .pounds) == 5)
        #expect(steps.equipmentRaw == "dumbbell@kilograms=2.5")

        steps.setStep(2, for: .dumbbell, unit: .kilograms)
        #expect(steps.equipmentRaw.isEmpty)
        steps.setStep(1, for: .barbell, unit: .kilograms)
        steps.setStep(nil, for: .barbell, unit: .kilograms)
        #expect(steps.equipmentRaw.isEmpty)
    }

    @Test("Korak vježbe vrijedi umjesto koraka opreme")
    func exerciseOverride() {
        var steps = WeightStepSettings()
        steps.setOverride(7, forExercise: "c:leg-press", unit: .kilograms)
        #expect(steps.step(forExercise: "c:leg-press", equipment: .machine, unit: .kilograms) == 7)
        #expect(steps.step(forExercise: "c:leg-press", equipment: .machine, unit: .pounds) == 10)
        #expect(steps.step(forExercise: "c:other", equipment: .machine, unit: .kilograms) == 5)

        steps.setOverride(nil, forExercise: "c:leg-press", unit: .kilograms)
        #expect(steps.override(forExercise: "c:leg-press", unit: .kilograms) == nil)
        #expect(steps.exercisesRaw.isEmpty)
    }

    @Test("Zapis se čita natrag, a neispravni unosi se preskaču")
    func encoding() {
        var steps = WeightStepSettings()
        steps.setStep(1.25, for: .barbell, unit: .kilograms)
        steps.setStep(2.5, for: .dumbbell, unit: .pounds)
        let id = UUID()
        steps.setOverride(4, forExercise: "u:\(id.uuidString)", unit: .kilograms)
        let copy = WeightStepSettings(equipmentRaw: steps.equipmentRaw, exercisesRaw: steps.exercisesRaw)
        #expect(copy == steps)

        let broken = WeightStepSettings(
            equipmentRaw: "barbell@kilograms=abc,=2,dumbbell@stone=2,machine@kilograms=-5,cable@kilograms=10",
            exercisesRaw: "c:x=2"
        )
        #expect(broken.step(for: .barbell, unit: .kilograms) == 2.5)
        #expect(broken.step(for: .machine, unit: .kilograms) == 5)
        #expect(broken.step(for: .cable, unit: .kilograms) == 10)
        #expect(broken.exercisesRaw.isEmpty)
    }

    @Test("Postavke spremaju korake u tekstualna polja")
    func userSettings() throws {
        let context = ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
        let settings = UserSettings()
        context.insert(settings)
        var steps = settings.weightSteps
        steps.setStep(2.5, for: .dumbbell, unit: .kilograms)
        steps.setOverride(7, forExercise: "c:leg-press", unit: .kilograms)
        settings.weightSteps = steps
        try context.save()

        #expect(settings.equipmentWeightStepsRaw == "dumbbell@kilograms=2.5")
        #expect(settings.exerciseWeightStepsRaw == "c:leg-press@kilograms=7.0")
        #expect(settings.weightSteps == steps)
    }

    @Test("Korak vježbe iz kataloga, vlastite vježbe i nepoznate vježbe")
    func resolver() throws {
        let catalog = try makeCatalog()
        let custom = CustomExercise(name: "Girja")
        custom.equipment = .kettlebell
        let settings = UserSettings()
        var steps = settings.weightSteps
        steps.setOverride(7, forExercise: "c:leg-press", unit: .kilograms)
        settings.weightSteps = steps

        let curl = ExerciseRef(catalogId: "dumbbell-curl", name: "Pregib")
        let press = ExerciseRef(catalogId: "leg-press", name: "Preša")
        let unknown = ExerciseRef(catalogId: "nema", name: "Nema")
        let step = WeightStepSettings.resolver(settings: settings, catalog: catalog, custom: [custom])
        #expect(step(curl) == 2)
        #expect(step(press) == 7)
        #expect(step(custom.ref) == 4)
        #expect(step(unknown) == 2.5)
        #expect(settings.weightStep(for: curl, catalog: catalog, custom: []) == 2)
        #expect(WeightStepSettings.equipment(of: custom.ref, catalog: catalog, custom: [custom]) == .kettlebell)

        settings.weightUnit = .pounds
        let pounds = WeightStepSettings.resolver(settings: settings, catalog: catalog, custom: [custom])
        #expect(pounds(curl) == 5)
        #expect(pounds(press) == 10)
        // Bez postavki vrijede zadani koraci u kilogramima.
        #expect(WeightStepSettings.resolver(settings: nil, catalog: nil, custom: [])(curl) == 2.5)
    }
}
