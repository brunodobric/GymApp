import Catalog
import Foundation
import SwiftData
import Units

/// Verzija 2 sheme: postavke dobivaju `modifiedAt` za "last write wins" nakon sinkronizacije (faza 12).
/// Ostali modeli su nepromijenjeni i dijele se s verzijom 1.
public enum GymSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            GymSchemaV1.CustomExercise.self,
            GymSchemaV1.Schedule.self,
            GymSchemaV1.ScheduleItem.self,
            GymSchemaV1.WorkoutTemplate.self,
            GymSchemaV1.TemplateExercise.self,
            GymSchemaV1.TemplateSet.self,
            GymSchemaV1.CycleOverride.self,
            GymSchemaV1.Session.self,
            GymSchemaV1.SessionExercise.self,
            GymSchemaV1.SetLog.self,
            GymSchemaV1.BodyMeasurement.self,
            GymSchemaV1.DashboardCard.self,
            GymSchemaV2.UserSettings.self,
        ]
    }
}

extension GymSchemaV2 {

    /// Postavke korisnika: u bazi mora postojati najviše jedan zapis (vidi `GymQueries.settings`).
    @Model
    public final class UserSettings {
        public var id: UUID = UUID()
        public var weightUnitRaw: String = WeightUnit.kilograms.rawValue
        public var defaultRestSeconds: Int = 90
        public var themeRaw: String = "system"
        public var accentColorRaw: String = "blue"
        public var effortScaleRaw: String = EffortScale.rpe.rawValue
        public var prEnabled: Bool = true
        /// Praćeni tipovi PR-ova odvojeni zarezom.
        public var trackedPRKindsRaw: String = "maxWeight,maxVolume,maxReps"
        public var restEndSoundEnabled: Bool = true
        /// Dostupne ploče u kilogramima, odvojene zarezom.
        public var availablePlatesRaw: String = "1.25,2.5,5,10,15,20,25"
        public var barbellWeightKg: Double = 20
        /// Onboarding. Prazan tekst znači da korisnik nije odgovorio.
        public var goalRaw: String = ""
        public var experienceRaw: String = ""
        /// Dostupna oprema (`Equipment.rawValue`) odvojena zarezom.
        public var equipmentRaw: String = ""
        public var trainingDaysPerWeek: Int?
        public var onboardingCompleted: Bool = false
        /// Povezivanje s Apple Zdravljem: odgovor iz onboardinga, mijenja se u Postavkama.
        public var wantsHealthKit: Bool = false
        public var notificationsEnabled: Bool = true
        /// Tijelo koje se crta na prikazu mišića (statistika, sažetak treninga).
        public var bodyMapFemale: Bool = false
        /// Zadnja promjena koju je napravio korisnik (nil za zadane postavke koje nitko nije mijenjao).
        /// Kad se nakon sinkronizacije nađe više zapisa, ostaje zadnje promijenjeni ("last write wins").
        public var modifiedAt: Date?

        public init() {}

        public var goal: TrainingGoal? {
            get { TrainingGoal(rawValue: goalRaw) }
            set { goalRaw = newValue?.rawValue ?? "" }
        }

        public var experience: ExperienceLevel? {
            get { ExperienceLevel(rawValue: experienceRaw) }
            set { experienceRaw = newValue?.rawValue ?? "" }
        }

        public var equipment: [Equipment] {
            get { equipmentRaw.split(separator: ",").compactMap { Equipment(rawValue: String($0)) } }
            set { equipmentRaw = newValue.map(\.rawValue).joined(separator: ",") }
        }

        public var effortScale: EffortScale {
            get { EffortScale(rawValue: effortScaleRaw) ?? .rpe }
            set { effortScaleRaw = newValue.rawValue }
        }

        public var weightUnit: WeightUnit {
            get { WeightUnit(rawValue: weightUnitRaw) ?? .kilograms }
            set { weightUnitRaw = newValue.rawValue }
        }

        public var theme: AppTheme {
            get { AppTheme(rawValue: themeRaw) ?? .system }
            set { themeRaw = newValue.rawValue }
        }

        public var accent: AccentChoice {
            get { AccentChoice(rawValue: accentColorRaw) ?? .blue }
            set { accentColorRaw = newValue.rawValue }
        }

        public var availablePlatesKg: [Double] {
            get { availablePlatesRaw.split(separator: ",").compactMap { Double($0) } }
            set { availablePlatesRaw = newValue.map { String($0) }.joined(separator: ",") }
        }

        public var trackedPRKinds: [String] {
            get { trackedPRKindsRaw.split(separator: ",").map(String.init) }
            set { trackedPRKindsRaw = newValue.joined(separator: ",") }
        }
    }
}
