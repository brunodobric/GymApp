import Catalog
import Foundation
import SwiftData
import Units

/// Odgovori iz onboardinga. Sve osim jedinica je neobavezno.
public struct OnboardingAnswers: Equatable, Sendable {
    public static let heightRangeCm: ClosedRange<Double> = 100...250
    public static let weightRangeKg: ClosedRange<Double> = 20...400
    public static let daysPerWeekRange: ClosedRange<Int> = 1...7

    public var goal: TrainingGoal?
    /// Spol, za DOTS bodove i tijelo na prikazu mišića.
    public var sex: Sex?
    public var unit: WeightUnit = .kilograms
    /// Visina u centimetrima.
    public var heightCm: Double?
    /// Težina onako kako je unesena, u odabranoj jedinici.
    public var weight: Double?
    public var wantsHealthKit = false
    public var experience: ExperienceLevel?
    public var equipment: [Equipment] = []
    public var daysPerWeek: Int?

    public init() {}

    /// Odgovori iz postavki, kad se profil ispunjava naknadno (kartica na Početnoj). Težina i visina ostaju
    /// prazne jer se upisuju kao nova mjerenja, a ne mijenjaju postojeća.
    public init(settings: UserSettings) {
        goal = settings.goal
        sex = settings.sex
        unit = settings.weightUnit
        wantsHealthKit = settings.wantsHealthKit
        experience = settings.experience
        equipment = settings.equipment
        daysPerWeek = settings.trainingDaysPerWeek
    }

    /// Težina u kg ili nil ako nije unesena ili je izvan razumnog raspona.
    public var weightKg: Double? {
        guard let weight else { return nil }
        let kg = WeightConversion.kilograms(from: weight, in: unit)
        return Self.weightRangeKg.contains(kg) ? kg : nil
    }

    public var validHeightCm: Double? {
        guard let heightCm, Self.heightRangeCm.contains(heightCm) else { return nil }
        return heightCm
    }

    public var validDaysPerWeek: Int? {
        guard let daysPerWeek, Self.daysPerWeekRange.contains(daysPerWeek) else { return nil }
        return daysPerWeek
    }
}

/// Primjenjuje odgovore iz onboardinga na postavke i tjelesna mjerenja.
public struct OnboardingApplier {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func apply(_ answers: OnboardingAnswers, now: Date = Date()) throws {
        let settings = try GymQueries(context: context).settings()
        settings.goal = answers.goal
        settings.weightUnit = answers.unit
        settings.wantsHealthKit = answers.wantsHealthKit
        settings.experience = answers.experience
        settings.equipment = answers.equipment
        settings.trainingDaysPerWeek = answers.validDaysPerWeek
        if let sex = answers.sex {
            settings.sex = sex
            settings.bodyMapFemale = sex == .female
        }
        settings.onboardingCompleted = true
        if let weightKg = answers.weightKg {
            context.insert(BodyMeasurement(kind: .weight, value: weightKg, date: now))
        }
        if let height = answers.validHeightCm {
            context.insert(BodyMeasurement(kind: .height, value: height, date: now))
        }
        try context.save()
    }

    /// "Preskoči" (i zatvaranje lista povlačenjem): ništa se ne sprema osim da je onboarding obavljen i odgovora
    /// o Apple Zdravlju, jer je dozvola možda već dana dodirom na "Poveži".
    public func skip(wantsHealthKit: Bool = false) throws {
        let settings = try GymQueries(context: context).settings()
        settings.wantsHealthKit = wantsHealthKit
        settings.onboardingCompleted = true
        try context.save()
    }
}

/// Brzi odabir opreme u onboardingu i profilu: "Teretana" odabire sve jednim dodirom.
/// Sprema se i dalje popis opreme (`UserSettings.equipment`), pa preset ne treba polje u shemi.
public enum EquipmentPreset: String, CaseIterable, Sendable {
    /// Teretana: sva oprema.
    case gym
    /// Kućna teretana: šipka sa stalkom i klupom, bučice, trake i šipka za zgibove (`.other`).
    case homeGym
    /// Bučice i trake.
    case dumbbells
    /// Bez opreme: samo vlastita težina.
    case bodyweightOnly

    public var equipment: [Equipment] {
        switch self {
        case .gym: Equipment.allCases
        case .homeGym: [.barbell, .dumbbell, .bodyweight, .bands, .other]
        case .dumbbells: [.dumbbell, .bodyweight, .bands]
        case .bodyweightOnly: [.bodyweight]
        }
    }

    /// Preset koji odgovara točno toj opremi, ili nil za vlastiti odabir.
    public static func matching(_ equipment: [Equipment]) -> EquipmentPreset? {
        allCases.first { Set($0.equipment) == Set(equipment) }
    }
}
