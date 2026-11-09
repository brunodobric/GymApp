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

    /// Postavke korisnika: u bazi mora postojati najviše jedan zapis (vidi `GymQueries.settings`).
    @Model
    public final class UserSettings {
        public var id: UUID = UUID()
        public var weightUnitRaw: String = WeightUnit.kilograms.rawValue
        /// Zadana pauza za izolacijske i ostale vježbe (i za sve vježbe prije nego što su postojale dvije).
        public var defaultRestSeconds: Int = 90
        /// Zadana pauza za složene vježbe (`RestDefaults`).
        public var compoundRestSeconds: Int = 150
        public var themeRaw: String = "system"
        public var accentColorRaw: String = "blue"
        public var effortScaleRaw: String = EffortScale.rpe.rawValue
        public var prEnabled: Bool = true
        /// Praćeni tipovi PR-ova odvojeni zarezom.
        public var trackedPRKindsRaw: String = "maxWeight,maxVolume,maxReps"
        /// Vježbe (`ExerciseRef.key`) koje je korisnik isključio iz rekorda, odvojene zarezom.
        public var prExcludedExercisesRaw: String = ""
        /// Razina statistike (`StatsDetail`): osnovna ili detaljna (Pro).
        public var statsDetailRaw: String = StatsDetail.basic.rawValue
        /// Spol (`Sex.rawValue`) za DOTS bodove. Prazan tekst znači da korisnik nije odgovorio.
        public var sexRaw: String = ""
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
        /// Podsjetnici rasporeda.
        public var notificationsEnabled: Bool = true
        /// Obavijest o kraju odmora kad je iPhone zaključan ili je trening sažet u karticu.
        public var restNotificationEnabled: Bool = true
        /// Trening pokrenut na iPhoneu pokreće i trening na satu (puls, kalorije, aplikacija ostaje otvorena).
        public var startsWatchWorkout: Bool = true
        /// Tijelo koje se crta na prikazu mišića (statistika, sažetak treninga).
        public var bodyMapFemale: Bool = false
        /// Live Activity prati temu i naglasnu boju aplikacije. Kad ne prati, koristi vlastite ispod.
        public var liveActivityFollowsApp: Bool = true
        public var liveActivityThemeRaw: String = "system"
        public var liveActivityAccentRaw: String = "blue"

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

        public var liveActivityTheme: AppTheme {
            get { AppTheme(rawValue: liveActivityThemeRaw) ?? .system }
            set { liveActivityThemeRaw = newValue.rawValue }
        }

        public var liveActivityAccent: AccentChoice {
            get { AccentChoice(rawValue: liveActivityAccentRaw) ?? .blue }
            set { liveActivityAccentRaw = newValue.rawValue }
        }

        /// Tema koju Live Activity stvarno koristi: aplikacijina ili vlastita.
        public var effectiveLiveActivityTheme: AppTheme {
            liveActivityFollowsApp ? theme : liveActivityTheme
        }

        /// Naglasna boja koju Live Activity stvarno koristi: aplikacijina ili vlastita.
        public var effectiveLiveActivityAccent: AccentChoice {
            liveActivityFollowsApp ? accent : liveActivityAccent
        }

        /// Uključuje ili isključuje praćenje aplikacije. Kad se isključi, vlastita tema i boja kreću od
        /// trenutnih aplikacijinih, da se Live Activity ne promijeni sama od sebe.
        public func setLiveActivityFollowsApp(_ follows: Bool) {
            guard follows != liveActivityFollowsApp else { return }
            if !follows {
                liveActivityTheme = theme
                liveActivityAccent = accent
            }
            liveActivityFollowsApp = follows
        }

        public var availablePlatesKg: [Double] {
            get { availablePlatesRaw.split(separator: ",").compactMap { Double($0) } }
            set { availablePlatesRaw = newValue.map { String($0) }.joined(separator: ",") }
        }

        public var sex: Sex? {
            get { Sex(rawValue: sexRaw) }
            set { sexRaw = newValue?.rawValue ?? "" }
        }

        public var statsDetail: StatsDetail {
            get { StatsDetail(rawValue: statsDetailRaw) ?? .basic }
            set { statsDetailRaw = newValue.rawValue }
        }

        /// Ključevi vježbi isključenih iz rekorda.
        public var prExcludedExerciseKeys: Set<String> {
            get { Set(prExcludedExercisesRaw.split(separator: ",").map(String.init)) }
            set { prExcludedExercisesRaw = newValue.sorted().joined(separator: ",") }
        }

        /// Uključuje ili isključuje vježbu iz rekorda.
        public func setRecordsEnabled(_ enabled: Bool, forExercise key: String) {
            guard !key.isEmpty else { return }
            var keys = prExcludedExerciseKeys
            if enabled { keys.remove(key) } else { keys.insert(key) }
            prExcludedExerciseKeys = keys
        }

        public var trackedPRKinds: [String] {
            get { trackedPRKindsRaw.split(separator: ",").map(String.init) }
            set { trackedPRKindsRaw = newValue.joined(separator: ",") }
        }
    }
}
