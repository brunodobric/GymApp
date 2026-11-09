import Catalog
import Foundation
import Units

/// Korak težine: razmak između dviju susjednih težina na kotačiću na iPhoneu, na gumbima + i − u
/// Live Activityju i na kartici treninga te za jedan klik Digital Crowna na satu.
///
/// Korak ovisi o opremi vježbe (bučice u jednoj teretani idu po 2 kg, u drugoj po 2,5 kg), a vježba može
/// imati vlastiti korak koji vrijedi umjesto koraka opreme. Korak je u jedinici prikaza (kg ili lbs), ne u
/// kilogramima: ploče i bučice postoje u svojoj jedinici, pa 5 lbs nije isto što i 2,27 kg na kotačiću.
/// Zato kilogrami i funte imaju odvojene postavke. Same težine i dalje se spremaju u kilogramima.
public struct WeightStepSettings: Equatable, Sendable {
    /// Korak po opremi, ključ je `Equipment.rawValue`.
    public private(set) var equipment: [Key: Double]
    /// Korak po vježbi, ključ je `ExerciseRef.key`.
    public private(set) var exercises: [Key: Double]

    public struct Key: Hashable, Sendable {
        public var id: String
        public var unit: WeightUnit
    }

    public init(equipmentRaw: String = "", exercisesRaw: String = "") {
        equipment = Self.decode(equipmentRaw)
        exercises = Self.decode(exercisesRaw)
    }

    // MARK: Ponuđeni i zadani koraci

    /// Koraci koji se mogu odabrati u postavkama i na vježbi.
    public static func choices(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .kilograms: [0.5, 1, 1.25, 2, 2.5, 4, 5, 10]
        case .pounds: [1, 2.5, 5, 10, 15, 20]
        }
    }

    /// Zadani korak opreme: najmanji uobičajeni skok s tom opremom. Bučice idu po 2 kg (10, 12, 14…),
    /// sprave i sajla po pločici od 5 kg, girje po 4 kg. Vježba bez opreme (vlastita vježba bez odabira)
    /// dobiva korak kao `other`.
    public static func defaultStep(for equipment: Equipment?, unit: WeightUnit) -> Double {
        switch (equipment ?? .other, unit) {
        case (.dumbbell, .kilograms): 2
        case (.cable, .kilograms), (.machine, .kilograms): 5
        case (.kettlebell, .kilograms): 4
        case (.cable, .pounds), (.machine, .pounds): 10
        case (_, .kilograms): 2.5
        case (_, .pounds): 5
        }
    }

    // MARK: Čitanje

    /// Korak opreme: postavka korisnika ili zadani korak.
    public func step(for equipment: Equipment?, unit: WeightUnit) -> Double {
        let kind = equipment ?? .other
        return self.equipment[Key(id: kind.rawValue, unit: unit)] ?? Self.defaultStep(for: kind, unit: unit)
    }

    /// Vlastiti korak vježbe, nil kad vježba prati korak opreme.
    public func override(forExercise key: String, unit: WeightUnit) -> Double? {
        exercises[Key(id: key, unit: unit)]
    }

    /// Korak koji vrijedi za vježbu: njezin vlastiti, inače korak opreme.
    public func step(forExercise key: String, equipment: Equipment?, unit: WeightUnit) -> Double {
        override(forExercise: key, unit: unit) ?? step(for: equipment, unit: unit)
    }

    // MARK: Promjena

    /// Postavlja korak opreme. Zadani korak (ili nil) briše postavku, pa vrijedi zadana vrijednost.
    public mutating func setStep(_ step: Double?, for equipment: Equipment, unit: WeightUnit) {
        let key = Key(id: equipment.rawValue, unit: unit)
        if let step, step > 0, step != Self.defaultStep(for: equipment, unit: unit) {
            self.equipment[key] = step
        } else {
            self.equipment[key] = nil
        }
    }

    /// Postavlja vlastiti korak vježbe. Nil vraća vježbu na korak opreme.
    public mutating func setOverride(_ step: Double?, forExercise key: String, unit: WeightUnit) {
        guard !key.isEmpty else { return }
        let entry = Key(id: key, unit: unit)
        if let step, step > 0 { exercises[entry] = step } else { exercises[entry] = nil }
    }

    public var equipmentRaw: String { Self.encode(equipment) }
    public var exercisesRaw: String { Self.encode(exercises) }

    // MARK: Zapis

    // Zapis je tekst (CloudKit ne voli rječnike): "dumbbell@kilograms=2,machine@pounds=10".
    // Ključevi vježbi ("c:<id>", "u:<UUID>") i opreme nemaju znakove "@", "=" ni ",".

    static func encode(_ values: [Key: Double]) -> String {
        values
            .map { key, value in "\(key.id)@\(key.unit.rawValue)=\(value)" }
            .sorted()
            .joined(separator: ",")
    }

    static func decode(_ raw: String) -> [Key: Double] {
        var result: [Key: Double] = [:]
        for entry in raw.split(separator: ",") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Double(parts[1]), value > 0 else { continue }
            let target = parts[0].split(separator: "@")
            guard target.count == 2, !target[0].isEmpty, let unit = WeightUnit(rawValue: String(target[1])) else { continue }
            result[Key(id: String(target[0]), unit: unit)] = value
        }
        return result
    }
}

extension WeightStepSettings {
    /// Oprema vježbe iz kataloga ili vlastite vježbe. Nil kad vježba nije nađena ili nema opremu.
    public static func equipment(
        of exercise: ExerciseRef, catalog: ExerciseCatalog?, custom: [CustomExercise]
    ) -> Equipment? {
        if let id = exercise.catalogId {
            return catalog?.exercise(withID: id)?.equipment
        }
        if let id = exercise.customExerciseId {
            return custom.first { $0.id == id }?.equipment
        }
        return nil
    }

    /// Korak težine po vježbi za mjesta koja nemaju ekran (snimka za sat, kontekst za sat, Live Activity).
    /// Postavke, katalog i oprema vlastitih vježbi čitaju se jednom, a ne za svaku vježbu.
    public static func resolver(
        settings: GymSchemaV1.UserSettings?, catalog: ExerciseCatalog?, custom: [CustomExercise]
    ) -> (ExerciseRef) -> Double {
        let steps = settings?.weightSteps ?? WeightStepSettings()
        let unit = settings?.weightUnit ?? .kilograms
        let customEquipment = Dictionary(custom.map { ($0.id, $0.equipment) }, uniquingKeysWith: { first, _ in first })
        return { exercise in
            let equipment: Equipment? = if let id = exercise.catalogId {
                catalog?.exercise(withID: id)?.equipment
            } else if let id = exercise.customExerciseId {
                customEquipment[id] ?? nil
            } else {
                nil
            }
            return steps.step(forExercise: exercise.key, equipment: equipment, unit: unit)
        }
    }
}

extension GymSchemaV1.UserSettings {
    /// Koraci težine po opremi i po vježbi (`WeightStepSettings`).
    public var weightSteps: WeightStepSettings {
        get { WeightStepSettings(equipmentRaw: equipmentWeightStepsRaw, exercisesRaw: exerciseWeightStepsRaw) }
        set {
            equipmentWeightStepsRaw = newValue.equipmentRaw
            exerciseWeightStepsRaw = newValue.exercisesRaw
        }
    }

    /// Korak težine za vježbu u jedinici korisnika.
    public func weightStep(for exercise: ExerciseRef, catalog: ExerciseCatalog?, custom: [CustomExercise]) -> Double {
        weightSteps.step(
            forExercise: exercise.key,
            equipment: WeightStepSettings.equipment(of: exercise, catalog: catalog, custom: custom),
            unit: weightUnit
        )
    }
}
