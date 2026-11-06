import Foundation

// Pojmovi kataloga. Vrijednosti (rawValue) su stabilni ključevi u catalog.json i u korisničkoj bazi,
// a nazivi za prikaz dolaze iz lokalizacije u aplikaciji.

/// Naše kategorije (specifikacija, odjeljak 1).
public enum ExerciseCategory: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, arms, legs, core, cardio
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
