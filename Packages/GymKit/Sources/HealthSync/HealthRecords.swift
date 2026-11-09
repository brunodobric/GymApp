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

/// Jedan trening u Zdravlju. Trening iz aplikacije može biti više njih jedan za drugim (snaga pa kardio),
/// jer jedan HealthKit trening ne može miješati vrste aktivnosti (osim triatlona).
public struct HealthWorkoutSegment: Sendable, Equatable {
    public var activity: HealthActivity
    public var start: Date
    public var end: Date

    public init(activity: HealthActivity, start: Date, end: Date) {
        self.activity = activity
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Trening koji treba spremiti u Zdravlje.
public struct HealthWorkoutExport: Sendable, Equatable {
    public var sessionId: UUID
    /// Treninzi u Zdravlju redom po vremenu; uvijek barem jedan. Bez kardio vježbi jedan trening za cijeli trening.
    public var segments: [HealthWorkoutSegment]

    /// Vrsta glavnog treninga.
    public var activity: HealthActivity { segments[primaryIndex].activity }
    public var start: Date { segments.first?.start ?? .distantPast }
    public var end: Date { segments.last?.end ?? .distantPast }
    /// Glavni trening: najdulji trening snage, a bez snage najdulji trening. Njegov id ide u `Session`.
    public var primaryIndex: Int {
        let strength = segments.indices.filter { !segments[$0].activity.isCardio }
        let candidates = strength.isEmpty ? Array(segments.indices) : strength
        return candidates.max { segments[$0].duration < segments[$1].duration } ?? 0
    }

    /// Kardio blokovi razmaknuti najviše ovoliko su jedan kardio trening (prijelaz sa sprave na spravu).
    public static let cardioJoinGap: TimeInterval = 5 * 60
    /// Kraći dio od ovoga ne ide u Zdravlje kao zaseban trening.
    public static let minimumSegment: TimeInterval = 60

    /// Spremaju se samo završeni treninzi koje je vodio iPhone, koji još nisu u Zdravlju i nisu iz njega uvezeni.
    /// Trening koji vodi sat sprema sam sat (`HKWorkoutSession`, faza 8), a isto i trening s iPhonea
    /// za koji je sat pokrenuo sesiju u Zdravlju (`Session.healthRecordedByWatch`).
    ///
    /// Kardio vježbe (`isCardio` po ključu `ExerciseRef.key`) postaju zasebni kardio treninzi u vremenu
    /// svojih serija (kvačica minus trajanje serije), a snaga ostaje u razmacima između njih.
    public static func make(for session: Session, isCardio: (String) -> Bool = { _ in false }) -> HealthWorkoutExport? {
        guard session.state == .finished,
              session.controllingDevice == .phone,
              !session.healthRecordedByWatch,
              session.healthKitWorkoutId == nil,
              !session.isImportedFromWorkoutsApp,
              let end = session.endedAt, end > session.startedAt
        else { return nil }
        return HealthWorkoutExport(
            sessionId: session.id,
            segments: segments(of: session, start: session.startedAt, end: end, isCardio: isCardio)
        )
    }

    static func segments(
        of session: Session, start: Date, end: Date, isCardio: (String) -> Bool
    ) -> [HealthWorkoutSegment] {
        let whole = [HealthWorkoutSegment(activity: .forExport(of: session.kind), start: start, end: end)]
        guard session.kind == .strength else { return whole }

        var cardio: [(start: Date, end: Date)] = []
        var strengthSets: [Date] = []
        for exercise in session.orderedExercises where !exercise.isRemoved {
            let done = exercise.orderedSets.filter(\.isCompleted)
            guard isCardio(exercise.exerciseKey) else {
                strengthSets += done.compactMap(\.completedAt)
                continue
            }
            for set in done {
                guard let finished = set.completedAt, let seconds = set.durationSeconds, seconds > 0 else { continue }
                let from = max(start, finished.addingTimeInterval(-TimeInterval(seconds)))
                let to = min(end, finished)
                if to > from { cardio.append((from, to)) }
            }
        }
        guard !cardio.isEmpty else { return whole }
        guard !strengthSets.isEmpty else {
            return [HealthWorkoutSegment(activity: .mixedCardio, start: start, end: end)]
        }

        // Kardio blokovi: bliski se spajaju, a blok blizu početka ili kraja treninga dobiva i taj rub.
        var blocks: [(start: Date, end: Date)] = []
        for interval in cardio.sorted(by: { $0.start < $1.start }) {
            if let last = blocks.last, interval.start.timeIntervalSince(last.end) <= cardioJoinGap {
                blocks[blocks.count - 1].end = max(last.end, interval.end)
            } else {
                blocks.append(interval)
            }
        }
        if let first = blocks.first, first.start.timeIntervalSince(start) <= cardioJoinGap { blocks[0].start = start }
        if let last = blocks.last, end.timeIntervalSince(last.end) <= cardioJoinGap { blocks[blocks.count - 1].end = end }

        // Snaga je u razmacima između kardio blokova, ako je u razmaku označena barem jedna serija snage.
        var result: [HealthWorkoutSegment] = []
        var cursor = start
        func addStrength(until limit: Date) {
            guard limit.timeIntervalSince(cursor) >= minimumSegment,
                  strengthSets.contains(where: { $0 > cursor && $0 <= limit }) else { return }
            result.append(HealthWorkoutSegment(activity: .traditionalStrengthTraining, start: cursor, end: limit))
        }
        for block in blocks {
            addStrength(until: block.start)
            if block.end.timeIntervalSince(block.start) >= minimumSegment {
                result.append(HealthWorkoutSegment(activity: .mixedCardio, start: block.start, end: block.end))
            }
            cursor = max(cursor, block.end)
        }
        addStrength(until: end)
        return result.isEmpty ? whole : result
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
