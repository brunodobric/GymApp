import Foundation

// Vrijednosti se u bazi spremaju kao tekst (rawValue), a modeli ih izlažu preko računanih svojstava.
// Tako se novi slučajevi mogu dodati bez migracije sheme, a CloudKit vidi samo osnovne tipove.

public enum SetKind: String, Codable, CaseIterable, Sendable {
    case working
    case warmUp
}

public enum WorkoutKind: String, Codable, CaseIterable, Sendable {
    case strength
    case cardio
}

public enum SessionState: String, Codable, CaseIterable, Sendable {
    case active
    case finished
    case discarded
}

public enum DeviceRole: String, Codable, CaseIterable, Sendable {
    case phone
    case watch
}

public enum ScheduleItemKind: String, Codable, CaseIterable, Sendable {
    case workout
    case restDay
}

public enum ReminderMode: String, Codable, CaseIterable, Sendable {
    case fixedDays
    case flexible
}

public enum CycleOverrideKind: String, Codable, CaseIterable, Sendable {
    case skipWorkout
    case removeExercise
    case replaceExercise
    /// Trening iz niza odrađen u ovom ciklusu. Starije verzije ga čitaju kao preskakanje,
    /// što za njih znači isto: raspored ga prelazi.
    case completedWorkout
}

public enum BodyMeasurementKind: String, Codable, CaseIterable, Sendable {
    case weight
    case height
    case waist
    case chest
    case arm
    case leg
    case custom
}

public enum MeasurementSource: String, Codable, CaseIterable, Sendable {
    case manual
    case healthKit
}

/// Cilj treninga iz onboardinga.
public enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case hypertrophy
    case strength
    case recomposition
    case generalFitness
}

public enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case advanced
}

/// Tema aplikacije: prati sustav ili je uvijek svijetla odnosno tamna.
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// Naglasna boja aplikacije. `blue` je zadana Apolon plava (`AccentPalette` u aplikaciji).
/// Zelene, crvene i narančaste nema jer znače završenu seriju, brisanje i zagrijavanje:
/// spremljena stara vrijednost ("green", "orange", "red") čita se kao zadana.
public enum AccentChoice: String, Codable, CaseIterable, Sendable {
    case blue, indigo, purple, pink, teal, graphite

    /// Nepoznata vrijednost (stara boja iz konteksta sata ili kopije) dekodira se kao zadana,
    /// da zbog boje ne padne dekodiranje cijelog zapisa.
    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = AccentChoice(rawValue: rawValue) ?? .blue
    }
}

/// Razina statistike: osnovna (pregled, status, najviše tri rekorda) ili detaljna (sve kartice i podaci).
public enum StatsDetail: String, Codable, CaseIterable, Sendable {
    case basic
    case pro
}

/// Spol za izračune koji ga trebaju (DOTS bodovi). Neobavezan: nil znači da korisnik nije odgovorio.
public enum Sex: String, Codable, CaseIterable, Sendable {
    case female
    case male
}

public enum EffortScale: String, Codable, CaseIterable, Sendable {
    case rpe
    case rir
}

/// RPE se uvijek sprema kao broj od 1 do 10 u koracima od 0,5. RIR je izveden: RIR = 10 − RPE.
public enum RPE {
    public static let range: ClosedRange<Double> = 1...10
    public static let step = 0.5

    public static func isValid(_ value: Double) -> Bool {
        guard range.contains(value) else { return false }
        let steps = value / step
        return abs(steps - steps.rounded()) < 1e-9
    }

    /// Ponavljanja u rezervi za prikaz kad je odabran RIR.
    public static func rir(fromRPE rpe: Double) -> Double {
        10 - rpe
    }

    public static func rpe(fromRIR rir: Double) -> Double {
        10 - rir
    }
}
