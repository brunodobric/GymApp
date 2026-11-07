import Catalog
import Foundation
import Models

/// Vrijednosti jedne serije bez veze s bazom: ulaz za volumen, PR-ove i smart defaults.
/// Težine su uvijek u kilogramima.
public struct SetValues: Equatable, Sendable {
    public var kind: SetKind
    public var weightKg: Double?
    public var reps: Int?
    /// Dodatna težina (vlastita težina + teret) ili pomoć (potpomognuta vježba).
    public var extraWeightKg: Double?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?

    public init(
        kind: SetKind = .working,
        weightKg: Double? = nil,
        reps: Int? = nil,
        extraWeightKg: Double? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rpe: Double? = nil
    ) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.extraWeightKg = extraWeightKg
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rpe = rpe
    }
}

extension SetLog {
    public var values: SetValues {
        SetValues(
            kind: kind, weightKg: weightKg, reps: reps, extraWeightKg: extraWeightKg,
            durationSeconds: durationSeconds, distanceMeters: distanceMeters, rpe: rpe
        )
    }
}

public enum SetMetrics {

    /// Volumen serije po vrsti unosa (specifikacija, odjeljak 2). Warm-up se nikad ne računa.
    /// Vlastita težina, potpomognuta i vježbe s trajanjem nemaju volumen težine.
    public static func volume(_ set: SetValues, inputType: ExerciseInputType) -> Double {
        guard set.kind == .working else { return 0 }
        switch inputType {
        case .weightReps: return (set.weightKg ?? 0) * Double(set.reps ?? 0)
        case .weightedBodyweight: return (set.extraWeightKg ?? 0) * Double(set.reps ?? 0)
        case .bodyweight, .assisted, .duration, .durationDistance: return 0
        }
    }

    public enum OneRepMaxFormula: Sendable {
        case epley, brzycki
    }

    /// Procjena 1RM. `rir` su ponavljanja u rezervi: formule pretpostavljaju seriju do otkaza, pa se računa
    /// s ponavljanjima do otkaza (reps + RIR). Vraća nil kad se ne može izračunati (bez težine ili ponavljanja,
    /// Brzycki od 37 ponavljanja do otkaza).
    public static func estimatedOneRepMax(
        weightKg: Double, reps: Int, rir: Double = 0, formula: OneRepMaxFormula = .epley
    ) -> Double? {
        guard weightKg > 0, reps >= 1 else { return nil }
        let toFailure = Double(reps) + max(0, rir)
        if toFailure <= 1 { return weightKg }
        switch formula {
        case .epley: return weightKg * (1 + toFailure / 30)
        case .brzycki:
            guard toFailure < 37 else { return nil }
            return weightKg * 36 / (37 - toFailure)
        }
    }

    /// Najviše ponavljanja do otkaza s kojima je procjena 1RM pouzdana. Iznad toga formule brzo griješe
    /// (LeSuer i sur. 1997, Reynolds i sur. 2006).
    public static let reliableRepsToFailure = 12.0

    /// Ponavljanja u rezervi iz upisanog RPE-a (RIR = 10 − RPE). Bez RPE-a pretpostavlja se otkaz (RIR 0):
    /// procjena je tada malo niža, ali dosljedno, pa trend ostaje ispravan.
    public static func repsInReserve(_ set: SetValues) -> Double {
        guard let rpe = set.rpe else { return 0 }
        return max(0, 10 - rpe)
    }

    /// Teret serije za procjenu snage: težina ili dodatni teret uz vlastitu težinu. Nil za vrste bez tereta.
    public static func load(_ set: SetValues, inputType: ExerciseInputType) -> Double? {
        switch inputType {
        case .weightReps: set.weightKg
        case .weightedBodyweight: set.extraWeightKg
        case .bodyweight, .assisted, .duration, .durationDistance: nil
        }
    }

    /// Pouzdana procjena 1RM radne serije: s RIR-om iz RPE-a i samo do `reliableRepsToFailure` ponavljanja
    /// do otkaza. Nil za warm-up, vrste bez tereta i serije s previše ponavljanja.
    public static func strengthEstimate(
        _ set: SetValues, inputType: ExerciseInputType, formula: OneRepMaxFormula = .epley
    ) -> Double? {
        guard set.kind == .working, let load = load(set, inputType: inputType), let reps = set.reps, reps >= 1 else { return nil }
        let rir = repsInReserve(set)
        guard Double(reps) + rir <= reliableRepsToFailure else { return nil }
        return estimatedOneRepMax(weightKg: load, reps: reps, rir: rir, formula: formula)
    }

    /// Najmanji RPE s kojim se serija broji kao tvrda (RPE 6 = RIR 4).
    public static let minimumHardRPE = 6.0

    /// Tvrda serija: radna, bez upisanog RPE-a ispod `minimumHardRPE` (Robinson i sur. 2024).
    public static func isHard(_ set: SetValues) -> Bool {
        guard set.kind == .working else { return false }
        if let rpe = set.rpe, rpe < minimumHardRPE { return false }
        return true
    }

    /// Ima li serija sve što vrsta unosa traži da bi se mogla označiti kvačicom.
    public static func isComplete(_ set: SetValues, inputType: ExerciseInputType) -> Bool {
        switch inputType {
        case .weightReps: set.weightKg != nil && (set.reps ?? 0) > 0
        case .bodyweight, .weightedBodyweight, .assisted: (set.reps ?? 0) > 0
        case .duration: (set.durationSeconds ?? 0) > 0
        case .durationDistance: (set.durationSeconds ?? 0) > 0 || (set.distanceMeters ?? 0) > 0
        }
    }
}

public enum SmartDefaults {

    /// Zadane vrijednosti za seriju na zadanoj poziciji, iz zadnjeg izvođenja iste vježbe.
    /// Pozicija se računa zasebno za warm-up i radne serije. Ako je novih serija više nego prošli put,
    /// koristi se zadnja prošla serija iste vrste. RPE se nikad ne prenosi.
    public static func defaults(forPosition position: Int, kind: SetKind, previous: [SetValues]) -> SetValues? {
        let sameKind = previous.filter { $0.kind == kind }
        guard !sameKind.isEmpty else { return nil }
        let base = sameKind[min(max(position, 0), sameKind.count - 1)]
        return SetValues(
            kind: kind, weightKg: base.weightKg, reps: base.reps, extraWeightKg: base.extraWeightKg,
            durationSeconds: base.durationSeconds, distanceMeters: base.distanceMeters, rpe: nil
        )
    }
}

extension GymQueries {
    /// Završene serije zadnjeg izvođenja vježbe: prethodne vrijednosti u retku serije, u kartici treninga
    /// i u Live Activityju te izvor smart defaultsa. Prazno kad vježba još nije rađena.
    public func previousSetValues(of exercise: ExerciseRef) throws -> [SetValues] {
        try lastPerformance(of: exercise)?.orderedSets.filter(\.isCompleted).map(\.values) ?? []
    }
}
