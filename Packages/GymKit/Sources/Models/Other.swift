import Catalog
import Foundation
import SwiftData
import Units

extension GymSchemaV1 {

    @Model
    public final class BodyMeasurement {
        public var id: UUID = UUID()
        public var kindRaw: String = BodyMeasurementKind.weight.rawValue
        public var customName: String?
        /// Metričke jedinice: kg za težinu, cm za ostalo.
        public var value: Double = 0
        public var date: Date = Date()
        public var sourceRaw: String = MeasurementSource.manual.rawValue
        /// UUID uzorka u Zdravlju za mjerenja uvezena iz HealthKita (sprječava dvostruki uvoz).
        public var healthKitSampleId: UUID?

        public init(kind: BodyMeasurementKind, value: Double, date: Date = Date(), source: MeasurementSource = .manual) {
            self.kindRaw = kind.rawValue
            self.value = value
            self.date = date
            self.sourceRaw = source.rawValue
        }

        public var kind: BodyMeasurementKind {
            get { BodyMeasurementKind(rawValue: kindRaw) ?? .custom }
            set { kindRaw = newValue.rawValue }
        }

        public var source: MeasurementSource {
            get { MeasurementSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }
    }

    /// Kartica na Početnoj. To su kartice u aplikaciji, ne widgeti početnog zaslona.
    @Model
    public final class DashboardCard {
        public var id: UUID = UUID()
        public var kindRaw: String = ""
        public var orderIndex: Int = 0
        /// Postavke kartice kao JSON tekst.
        public var settingsJSON: String = ""

        public init(kindRaw: String, orderIndex: Int) {
            self.kindRaw = kindRaw
            self.orderIndex = orderIndex
        }
    }

    /// Postavke u verziji 1 sheme. Zamrznuto: služi samo za migraciju, trenutna verzija je `GymSchemaV2.UserSettings`.
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

        public init() {}
    }
}
