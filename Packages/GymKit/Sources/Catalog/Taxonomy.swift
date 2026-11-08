import Foundation

// Pojmovi kataloga. Vrijednosti (rawValue) su stabilni ključevi u catalog.json i u korisničkoj bazi,
// a nazivi za prikaz dolaze iz lokalizacije u aplikaciji.

/// Naše kategorije (specifikacija, odjeljak 1).
public enum ExerciseCategory: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, arms, legs, core, cardio
}

/// Vrsta vježbe, neovisno o dijelu tijela. Početna kataloga grupira vježbe po vrsti.
/// Kardio vježbe su uvijek i u kategoriji `cardio`. Redoslijed slučajeva je redoslijed prikaza.
public enum ExerciseKind: String, Codable, CaseIterable, Sendable {
    /// Dinamične vježbe pokretljivosti prije treninga (MoveKit obrazac Mobility).
    case warmUp
    /// Vježbe snage (sve što nije kardio, zagrijavanje ni istezanje).
    case strength
    /// Statično istezanje (MoveKit obrazac Stretch).
    case stretching
    case cardio

    /// Vrsta kad je izvor ne navodi (stariji catalog.json, vlastite vježbe): kardio po kategoriji,
    /// inače snaga.
    public static func fallback(for category: ExerciseCategory?) -> ExerciseKind {
        category == .cardio ? .cardio : .strength
    }
}

/// Naši mišići. MoveKit nazive mišića prevodi CatalogBuilder (Tools/CatalogBuilder/mapping.json).
public enum Muscle: String, Codable, CaseIterable, Sendable {
    case chest, shoulders, triceps, biceps, forearms
    case lats
    case middleBack = "middle back"
    case lowerBack = "lower back"
    case traps, neck, quadriceps, hamstrings, glutes, calves, adductors, abductors, abdominals
}

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case barbell, ezBar, dumbbell, cable, machine, bodyweight, kettlebell, bands, other
}

public enum Level: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, advanced
}

public enum Mechanic: String, Codable, CaseIterable, Sendable {
    case compound, isolation
}

public enum MovementType: String, Codable, CaseIterable, Sendable {
    case push, pull, legs
}

/// Vrsta unosa vježbe: određuje polja u retku serije i način računanja volumena (specifikacija, odjeljak 2).
public enum ExerciseInputType: String, Codable, CaseIterable, Sendable {
    case weightReps
    case bodyweight
    case weightedBodyweight
    case assisted
    case duration
    case durationDistance
}
