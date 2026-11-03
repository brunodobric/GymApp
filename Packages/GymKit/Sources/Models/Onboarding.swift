import Catalog
import Foundation
import SwiftData
import Units

/// Odgovori iz onboardinga. Sve osim jedinica i odgovora o Apple Zdravlju je neobavezno.
public struct OnboardingAnswers: Equatable, Sendable {
    public static let heightRangeCm: ClosedRange<Double> = 100...250
    public static let weightRangeKg: ClosedRange<Double> = 20...400
    public static let daysPerWeekRange: ClosedRange<Int> = 1...7

    public var goal: TrainingGoal?
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
        settings.onboardingCompleted = true
        settings.modifiedAt = now
        if let weightKg = answers.weightKg {
            context.insert(BodyMeasurement(kind: .weight, value: weightKg, date: now))
        }
        if let height = answers.validHeightCm {
            context.insert(BodyMeasurement(kind: .height, value: height, date: now))
        }
        try context.save()
    }

    /// "Preskoči": ništa se ne sprema osim da je onboarding obavljen.
    public func skip() throws {
        try GymQueries(context: context).settings().onboardingCompleted = true
        try context.save()
    }
}
