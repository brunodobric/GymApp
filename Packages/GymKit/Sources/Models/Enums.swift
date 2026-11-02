import Foundation

// Vrijednosti se u bazi spremaju kao tekst (rawValue), a modeli ih izlažu preko računanih svojstava.
// Tako se novi slučajevi mogu dodati bez migracije sheme, a CloudKit vidi samo osnovne tipove.

/// Vrsta unosa vježbe: određuje polja u retku serije i način računanja volumena (specifikacija, odjeljak 2).
public enum ExerciseInputType: String, Codable, CaseIterable, Sendable {
    case weightReps
    case bodyweight
    case weightedBodyweight
    case assisted
    case duration
    case durationDistance
}

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
