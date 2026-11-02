import Catalog
import Foundation
import Models

/// Regije tijela za heatmap. Nazivi su isti kao u katalogu (`primaryRegions`).
public enum BodyRegion {
    /// Sve regije, redom za prikaz: prednja strana pa stražnja.
    public static let all: [String] = [
        "chest", "shoulders", "biceps", "forearms", "abs", "quads", "innerThigh", "outerThigh",
        "traps", "upperBack", "lats", "triceps", "lowerBack", "glutes", "hamstrings", "calves"
    ]

    /// Regija za mišić. Koristi se za vlastite vježbe, koje nemaju regije iz kataloga.
    public static func region(for muscle: Muscle) -> String {
        switch muscle {
        case .chest: "chest"
        case .shoulders: "shoulders"
        case .triceps: "triceps"
        case .biceps: "biceps"
        case .forearms: "forearms"
        case .lats: "lats"
        case .middleBack: "upperBack"
        case .lowerBack: "lowerBack"
        case .traps, .neck: "traps"
        case .quadriceps: "quads"
        case .hamstrings: "hamstrings"
        case .glutes: "glutes"
        case .calves: "calves"
        case .adductors: "innerThigh"
        case .abductors: "outerThigh"
        case .abdominals: "abs"
        }
    }
}

/// Gradi `ExerciseInfoProvider` iz kataloga i vlastitih vježbi, po ključu `ExerciseRef.key`.
public enum ExerciseInfoBuilder {
    public static func provider(
        catalog: ExerciseCatalog?, custom: [CustomExercise]
    ) -> ExerciseInfoProvider {
        var table: [String: ExerciseInfo] = [:]
        for exercise in catalog?.exercises ?? [] {
            table["c:\(exercise.id)"] = ExerciseInfo(
                primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles,
                primaryRegions: exercise.primaryRegions, secondaryRegions: exercise.secondaryRegions
            )
        }
        for exercise in custom {
            let muscles = exercise.muscles
            var regions: [String] = []
            for muscle in muscles {
                let region = BodyRegion.region(for: muscle)
                if !regions.contains(region) { regions.append(region) }
            }
            table["u:\(exercise.id.uuidString)"] = ExerciseInfo(
                primary: muscles, primaryRegions: regions
            )
        }
        return { table[$0] }
    }
}
