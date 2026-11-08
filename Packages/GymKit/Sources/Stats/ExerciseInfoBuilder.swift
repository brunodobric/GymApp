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

    /// Glavne mišićne skupine za koje statistika javlja da zaostaju (ispod 5 tvrdih serija tjedno).
    /// Manje regije (podlaktice, trapez, donja leđa, bedra sa strane) dobivaju dovoljno rada iz drugih vježbi.
    public static let major: [String] = [
        "chest", "shoulders", "biceps", "triceps", "upperBack", "lats", "quads", "hamstrings", "glutes", "calves"
    ]

    /// Skupina mišića koja ima svoju boju u sučelju (čipovi, graf mišića). Bliske regije dijele boju,
    /// da paleta ostane mala: sva leđa su jedna boja, sve noge osim gluteusa druga.
    public enum ColorGroup: CaseIterable, Sendable {
        case chest, shoulders, biceps, triceps, forearms, core, back, legs, glutes
    }

    /// Boja regije; nepoznata regija nema boju.
    public static func colorGroup(for region: String) -> ColorGroup? {
        switch region {
        case "chest": .chest
        case "shoulders": .shoulders
        case "biceps": .biceps
        case "triceps": .triceps
        case "forearms": .forearms
        case "abs": .core
        case "traps", "upperBack", "lats", "lowerBack": .back
        case "quads", "hamstrings", "innerThigh", "outerThigh", "calves": .legs
        case "glutes": .glutes
        default: nil
        }
    }

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
                primaryRegions: exercise.primaryRegions, secondaryRegions: exercise.secondaryRegions,
                isCompound: exercise.mechanic.map { $0 == .compound }, isCardio: exercise.kind == .cardio
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
                primary: muscles, primaryRegions: regions,
                isCardio: exercise.kind == .cardio
            )
        }
        return { table[$0] }
    }

    /// Je li vježba kardio, za `SessionCardio` i sažetak treninga. Nepoznata vježba nije kardio.
    public static func isCardio(_ info: @escaping ExerciseInfoProvider) -> (String) -> Bool {
        { info($0)?.isCardio == true }
    }
}
