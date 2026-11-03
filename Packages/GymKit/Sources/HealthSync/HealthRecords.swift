import Foundation
import Models

// Podaci iz Apple Zdravlja u obliku neovisnom o HealthKitu. Aplikacija pretvara HealthKit objekte
// u ove vrijednosti, a logika uvoza i izvoza radi samo s njima (i zato se može testirati na Macu).

/// Vrsta aktivnosti treninga u Zdravlju. Pokriva vrste koje aplikacija uvozi ili sprema; ostale su `other`.
public enum HealthActivity: String, Codable, CaseIterable, Sendable {
    case running
    case walking
    case hiking
    case cycling
    case swimming
    case rowing
    case elliptical
    case stairs
    case highIntensityIntervalTraining
    case mixedCardio
    case jumpRope
    case crossCountrySkiing
    case dance
    case traditionalStrengthTraining
    case functionalStrengthTraining
    case coreTraining
    case other

    /// Kardio vrste se uvoze u povijest. Snaga i ostalo ne: trening snage vodi se u ovoj aplikaciji.
    public var isCardio: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling, .swimming, .rowing, .elliptical, .stairs,
             .highIntensityIntervalTraining, .mixedCardio, .jumpRope, .crossCountrySkiing, .dance:
            true
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .other:
            false
        }
    }

    /// Vrsta pod kojom se trening iz aplikacije sprema u Zdravlje.
    public static func forExport(of kind: WorkoutKind) -> HealthActivity {
        switch kind {
        case .strength: .traditionalStrengthTraining
        case .cardio: .mixedCardio
        }
    }
}

/// Trening pročitan iz Zdravlja.
public struct HealthWorkoutRecord: Sendable, Equatable {
    /// UUID uzorka u HealthKitu (isti na svim uređajima korisnika).
    public var uuid: UUID
    public var activity: HealthActivity
    public var start: Date
    public var end: Date
    /// Izvor (aplikacija ili uređaj) koji je zapisao trening.
    public var sourceBundleIdentifier: String
    /// `HKMetadataKeyExternalUUID`: kod treninga koje sprema ova aplikacija to je `Session.id`.
    public var externalUUID: UUID?
    public var activeEnergyKilocalories: Double?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?

    public init(
        uuid: UUID, activity: HealthActivity, start: Date, end: Date, sourceBundleIdentifier: String,
        externalUUID: UUID? = nil, activeEnergyKilocalories: Double? = nil,
        distanceMeters: Double? = nil, averageHeartRate: Double? = nil
    ) {
        self.uuid = uuid
        self.activity = activity
        self.start = start
        self.end = end
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.externalUUID = externalUUID
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
    }

    /// Appleovi izvori: aplikacija Trening na satu (`com.apple.health.<uređaj>`) i Fitness na iPhoneu.
    public var isFromApple: Bool {
        sourceBundleIdentifier.hasPrefix("com.apple.")
    }
}

/// Mjerenje tijela pročitano iz Zdravlja: težina u kg ili visina u cm.
public struct HealthBodySample: Sendable, Equatable {
    public var uuid: UUID
    public var kind: BodyMeasurementKind
    public var value: Double
    public var date: Date

    public init(uuid: UUID, kind: BodyMeasurementKind, value: Double, date: Date) {
        self.uuid = uuid
        self.kind = kind
        self.value = value
        self.date = date
    }
}

/// Trening koji treba spremiti u Zdravlje.
public struct HealthWorkoutExport: Sendable, Equatable {
    public var sessionId: UUID
    public var activity: HealthActivity
    public var start: Date
    public var end: Date

    /// Spremaju se samo završeni treninzi koje je vodio iPhone, koji još nisu u Zdravlju i nisu iz njega uvezeni.
    /// Trening koji vodi sat sprema sam sat (`HKWorkoutSession`, faza 8).
    public static func make(for session: Session) -> HealthWorkoutExport? {
        guard session.state == .finished,
              session.controllingDevice == .phone,
              session.healthKitWorkoutId == nil,
              !session.isImportedFromWorkoutsApp,
              let end = session.endedAt, end > session.startedAt
        else { return nil }
        return HealthWorkoutExport(
            sessionId: session.id, activity: .forExport(of: session.kind), start: session.startedAt, end: end
        )
    }
}

/// Koliko daleko unatrag ide prvi uvoz nakon povezivanja. Kasniji uvozi uzimaju samo novo (anchor u aplikaciji).
public enum HealthImportWindow {
    public static let workoutDays = 30
    public static let bodyDays = 365

    public static func start(days: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -days, to: today) ?? today
    }
}
