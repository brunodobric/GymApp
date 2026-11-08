import Catalog
import Foundation
import Models
import SwiftData
import Training

/// Mišići i regije koje vježba opterećuje. Izvor je katalog ili vlastita vježba; pozivatelj ga daje po ključu vježbe.
public struct ExerciseInfo: Equatable, Sendable {
    public var primary: [Muscle]
    public var secondary: [Muscle]
    public var primaryRegions: [String]
    public var secondaryRegions: [String]
    /// Složena (više zglobova) ili izolacijska vježba iz kataloga. Nil kad se ne zna (vlastita vježba).
    public var isCompound: Bool?
    /// Kardio vježba (`ExerciseKind.cardio`). Ne broji se u serije po mišiću: 20 minuta trake nije serija
    /// za kvadricepse. Njezino vrijeme i udaljenost idu u kardio dio treninga (`SessionCardio`).
    public var isCardio: Bool

    public init(
        primary: [Muscle] = [], secondary: [Muscle] = [], primaryRegions: [String] = [], secondaryRegions: [String] = [],
        isCompound: Bool? = nil, isCardio: Bool = false
    ) {
        self.primary = primary
        self.secondary = secondary
        self.primaryRegions = primaryRegions
        self.secondaryRegions = secondaryRegions
        self.isCompound = isCompound
        self.isCardio = isCardio
    }
}

/// Daje podatke o vježbi prema `ExerciseRef.key`.
public typealias ExerciseInfoProvider = (String) -> ExerciseInfo?

public struct ExercisePoint: Equatable, Sendable {
    public let date: Date
    /// Najveća težina radne serije (kg); 0 kad vježba nema težinu.
    public let bestWeightKg: Double
    /// Ponavljanja najteže serije (uz istu težinu ona s najviše ponavljanja). Bez težine najviše ponavljanja.
    public let bestReps: Int
    /// Najbolja pouzdana procjena 1RM (s RIR-om, do 12 ponavljanja do otkaza); nil bez takve serije.
    public let estimatedOneRepMaxKg: Double?
    public let volumeKg: Double

    public init(date: Date, bestWeightKg: Double, bestReps: Int, estimatedOneRepMaxKg: Double?, volumeKg: Double) {
        self.date = date
        self.bestWeightKg = bestWeightKg
        self.bestReps = bestReps
        self.estimatedOneRepMaxKg = estimatedOneRepMaxKg
        self.volumeKg = volumeKg
    }
}

/// Opterećenje jedne regije u razdoblju grafa.
public struct MuscleLoad: Equatable, Sendable {
    /// Tonaža vježbi kojima je regija glavni mišić.
    public var volumeKg: Double
    /// Tvrde serije, pomoćne upola (`EffectiveSets`).
    public var sets: Double

    public init(volumeKg: Double = 0, sets: Double = 0) {
        self.volumeKg = volumeKg
        self.sets = sets
    }
}

public enum BucketSize: Sendable {
    case week
    case month
}

/// Jedan tjedan ili mjesec: serije po regiji tijela i ukupna tonaža.
public struct VolumeBucket: Equatable, Sendable {
    public let start: Date
    /// Ključ je regija tijela (`BodyRegion.all`).
    public var loads: [String: MuscleLoad]
    /// Ukupna tonaža razdoblja; svaka serija broji se jednom, bez obzira na broj regija vježbe.
    public var totalVolumeKg: Double
    /// Ukupan broj tvrdih serija; svaka serija broji se jednom.
    public var totalSets: Int

    public init(start: Date, loads: [String: MuscleLoad] = [:], totalVolumeKg: Double = 0, totalSets: Int = 0) {
        self.start = start
        self.loads = loads
        self.totalVolumeKg = totalVolumeKg
        self.totalSets = totalSets
    }
}

extension VolumeBucket {
    /// Dodaje tvrde serije snage iz treninga: tonaža i ukupan broj serija jednom po seriji, regije prema
    /// `EffectiveSets` (pomoćne upola). Kardio vježbe se preskaču.
    mutating func add(_ session: Session, info: ExerciseInfoProvider) {
        for exercise in session.orderedExercises where !exercise.isRemoved {
            guard let details = info(exercise.exerciseKey), !details.isCardio else { continue }
            let sets = EffectiveSets.hardSets(of: exercise)
            guard !sets.isEmpty else { continue }
            let volume = sets.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
            totalVolumeKg += volume
            totalSets += sets.count
            for (region, share) in EffectiveSets.regionCounts(hardSets: sets.count, info: details) {
                var load = loads[region] ?? MuscleLoad()
                load.sets += share.weighted
                if share.primary > 0 { load.volumeKg += volume }
                loads[region] = load
            }
        }
    }
}

public struct FrequencyPoint: Equatable, Sendable {
    public let weekStart: Date
    public let sessions: Int
}

public struct RecordEntry: Equatable, Sendable {
    public let date: Date
    public let exerciseKey: String
    public let exerciseName: String
    public let record: PersonalRecord
}

public struct RegionLoad: Equatable, Sendable {
    /// Broj treninga u kojima je regija dobila barem jednu cijelu seriju (glavnu ili dvije pomoćne).
    public var sessions: Int
    public var volumeKg: Double
    /// Tvrde serije u razdoblju, pomoćne upola.
    public var sets: Double
    /// Prosjek tvrdih serija tjedno u razdoblju.
    public var weeklySets: Double
    /// Prosjek treninga tjedno (prema `sessions`).
    public var sessionsPerWeek: Double
    public var lastTrained: Date?
    /// Boja heatmapa 0...1 na fiksnoj skali (`LoadScale`).
    public var intensity: Double

    public init(
        sessions: Int = 0, volumeKg: Double = 0, sets: Double = 0, weeklySets: Double = 0,
        sessionsPerWeek: Double = 0, lastTrained: Date? = nil, intensity: Double = 0
    ) {
        self.sessions = sessions
        self.volumeKg = volumeKg
        self.sets = sets
        self.weeklySets = weeklySets
        self.sessionsPerWeek = sessionsPerWeek
        self.lastTrained = lastTrained
        self.intensity = intensity
    }

    /// Razina na tjednoj skali (`LoadScale.weeklyLevel`).
    public var weeklyLevel: Int { LoadScale.weeklyLevel(weeklySets) }
}

/// Promjena snage jedne regije: prosjek mjesečnog nagiba procjene 1RM njenih glavnih vježbi.
public struct StrengthTrend: Equatable, Sendable {
    public let region: String
    /// Relativna promjena mjesečno (0,05 = +5 % mjesečno).
    public let change: Double
    /// Broj vježbi koje su rađene u oba razdoblja.
    public let exercises: Int
}

/// Statistika nad završenim treninzima. Računaju se samo završene radne serije; warm-up se nikad ne broji.
public struct StatisticsEngine {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Napredak vježbe

    /// Napredak jedne vježbe kroz vrijeme, od najstarijeg treninga.
    public func progress(
        of ref: ExerciseRef, formula: SetMetrics.OneRepMaxFormula = .epley
    ) throws -> [ExercisePoint] {
        let key = ref.key
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        var points: [ExercisePoint] = []
        for exercise in try context.fetch(descriptor) {
            guard let session = exercise.session, session.state == .finished,
                  let point = Self.point(of: exercise, date: session.startedAt, formula: formula) else { continue }
            points.append(point)
        }
        return points.sorted { $0.date < $1.date }
    }

    /// Točka napretka jednog izvođenja vježbe. Nil kad nema završenih radnih serija.
    static func point(of exercise: SessionExercise, date: Date, formula: SetMetrics.OneRepMaxFormula) -> ExercisePoint? {
        let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values).filter { $0.kind == .working }
        guard !sets.isEmpty else { return nil }
        let type = exercise.inputType
        var bestWeight = 0.0
        var bestReps = 0
        var oneRepMax: Double?
        for set in sets {
            // Težina i ponavljanja iz iste serije, da redak ne pokaže "85 kg × 7" kad je 85 kg dignuto 5 puta.
            let load = SetMetrics.load(set, inputType: type) ?? 0
            let reps = set.reps ?? 0
            if load > bestWeight || (load == bestWeight && reps > bestReps) {
                bestWeight = load
                bestReps = reps
            }
            // Samo pouzdane serije (do 12 ponavljanja do otkaza), s RIR-om iz RPE-a.
            if let estimate = SetMetrics.strengthEstimate(set, inputType: type, formula: formula) {
                oneRepMax = max(oneRepMax ?? 0, estimate)
            }
        }
        let volume = sets.reduce(0) { $0 + SetMetrics.volume($1, inputType: type) }
        return ExercisePoint(
            date: date, bestWeightKg: bestWeight, bestReps: bestReps, estimatedOneRepMaxKg: oneRepMax, volumeKg: volume
        )
    }

    // MARK: Serije po mišićnoj skupini

    /// Tvrde serije i tonaža po regiji tijela, za `count` tjedana ili mjeseci koji završavaju
    /// onim koji sadrži `now` (od najstarijeg prema najnovijem).
    public func volumeBuckets(
        size: BucketSize, count: Int, endingAt now: Date = Date(), calendar: Calendar = .current,
        info: ExerciseInfoProvider
    ) throws -> [VolumeBucket] {
        let starts = bucketStarts(size: size, count: count, now: now, calendar: calendar)
        guard let first = starts.first, let last = starts.last,
              let end = interval(of: size, containing: last, calendar: calendar)?.end else { return [] }
        var buckets = Dictionary(uniqueKeysWithValues: starts.map { ($0, VolumeBucket(start: $0)) })

        for session in try GymQueries(context: context).finishedSessions(from: first, to: end) {
            guard let start = interval(of: size, containing: session.startedAt, calendar: calendar)?.start,
                  var bucket = buckets[start] else { continue }
            bucket.add(session, info: info)
            buckets[start] = bucket
        }
        return starts.compactMap { buckets[$0] }
    }

    // MARK: Frekvencija

    /// Broj treninga po tjednu za zadnjih `weeks` tjedana.
    public func frequency(
        weeks: Int, endingAt now: Date = Date(), calendar: Calendar = .current
    ) throws -> [FrequencyPoint] {
        let starts = bucketStarts(size: .week, count: weeks, now: now, calendar: calendar)
        guard let first = starts.first, let last = starts.last,
              let end = interval(of: .week, containing: last, calendar: calendar)?.end else { return [] }
        var counts: [Date: Int] = [:]
        for session in try GymQueries(context: context).finishedSessions(from: first, to: end) {
            if let start = interval(of: .week, containing: session.startedAt, calendar: calendar)?.start {
                counts[start, default: 0] += 1
            }
        }
        return starts.map { FrequencyPoint(weekStart: $0, sessions: counts[$0] ?? 0) }
    }

    // MARK: Osobni rekordi

    /// Svi rekordi postavljeni kroz povijest, od najnovijeg. Svaki trening se uspoređuje samo s ranijima.
    /// Vježbe iz `excluding` (isključene u Postavkama) nemaju rekorda.
    public func personalRecords(
        kinds: Set<PRKind> = Set(PRKind.allCases), excluding excluded: Set<String> = []
    ) throws -> [RecordEntry] {
        guard !kinds.isEmpty else { return [] }
        let finished = SessionState.finished.rawValue
        let sessions = try context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished },
            sortBy: [SortDescriptor(\.startedAt)]
        ))
        // Sažeta povijest daje iste rekorde, a ne raste s brojem treninga.
        var history: [String: RecordHistory] = [:]
        var entries: [RecordEntry] = []
        for session in sessions {
            for exercise in session.orderedExercises where !exercise.isRemoved {
                let done = exercise.orderedSets.filter(\.isCompleted).map(\.values)
                let key = exercise.exerciseKey
                guard !done.isEmpty, !excluded.contains(key) else { continue }
                var past = history[key] ?? RecordHistory()
                let found = PersonalRecordDetector.records(
                    current: done, history: past, inputType: exercise.inputType, kinds: kinds, date: session.startedAt
                )
                for record in found {
                    entries.append(RecordEntry(
                        date: session.startedAt, exerciseKey: key, exerciseName: exercise.exerciseName, record: record
                    ))
                }
                past.add(done, inputType: exercise.inputType, date: session.startedAt)
                history[key] = past
            }
        }
        return entries.reversed()
    }

    // MARK: Body heatmap

    /// Opterećenje po regiji tijela u razdoblju: tvrde serije (pomoćne upola), prosjek serija tjedno i
    /// učestalost. Boja je na fiksnoj tjednoj skali (`LoadScale.weeklyLevel`), ne relativna.
    /// Ako je prvi trening u aplikaciji kasnije od `start`, tjedni se prosjek računa od tog treninga,
    /// da novi korisnik ne dobije razvodnjen prosjek.
    public func heatmap(from start: Date, until end: Date, info: ExerciseInfoProvider) throws -> [String: RegionLoad] {
        var result: [String: RegionLoad] = [:]
        for session in try GymQueries(context: context).finishedSessions(from: start, to: end) {
            var shares: [String: RegionShare] = [:]
            var volumes: [String: Double] = [:]
            for exercise in session.orderedExercises where !exercise.isRemoved {
                guard let details = info(exercise.exerciseKey), !details.isCardio else { continue }
                let sets = EffectiveSets.hardSets(of: exercise)
                guard !sets.isEmpty else { continue }
                let volume = sets.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
                for (region, share) in EffectiveSets.regionCounts(hardSets: sets.count, info: details) {
                    var total = shares[region] ?? RegionShare(primary: 0, secondary: 0)
                    total.primary += share.primary
                    total.secondary += share.secondary
                    shares[region] = total
                    volumes[region, default: 0] += share.primary > 0 ? volume : volume * EffectiveSets.secondaryWeight
                }
            }
            for (region, share) in shares {
                var load = result[region] ?? RegionLoad()
                load.sets += share.weighted
                load.volumeKg += volumes[region] ?? 0
                if share.weighted >= 1 {
                    load.sessions += 1
                    load.lastTrained = max(load.lastTrained ?? .distantPast, session.startedAt)
                }
                result[region] = load
            }
        }
        let weeks = try weeksCovered(from: start, until: end)
        for (region, load) in result {
            result[region]?.weeklySets = load.sets / weeks
            result[region]?.sessionsPerWeek = Double(load.sessions) / weeks
            result[region]?.intensity = LoadScale.intensity(level: LoadScale.weeklyLevel(load.sets / weeks))
        }
        return result
    }

    /// Broj tjedana razdoblja za prosjek, najmanje 1. Počinje najranije s prvim treningom u aplikaciji.
    func weeksCovered(from start: Date, until end: Date) throws -> Double {
        let first = try firstSessionDate() ?? start
        let from = max(start, first)
        return max(1, end.timeIntervalSince(from) / (7 * 24 * 3600))
    }

    // MARK: Trend snage

    /// Promjena snage po regiji: za svaku vježbu s težinom računa se mjesečni nagib procjene 1RM u zadnjih
    /// `2 × weeks` tjedana (`TrendAnalysis`, otporno na jedan loš ili iznimno dobar dan). Regija dobiva prosjek
    /// nagiba vježbi kojima je glavni mišić. Broje se pouzdane serije (do 12 ponavljanja do otkaza).
    /// Vježba treba barem `TrendAnalysis.minimumSessions` izvođenja. Poredak: od najvećeg rasta.
    public func strengthTrends(
        weeks: Int = 4, endingAt now: Date = Date(), info: ExerciseInfoProvider,
        formula: SetMetrics.OneRepMaxFormula = .epley
    ) throws -> [StrengthTrend] {
        let trends = try exerciseTrends(weeks: weeks * 2, endingAt: now, info: info, formula: formula)
        var changes: [String: [Double]] = [:]
        for trend in trends {
            guard let monthly = trend.trend.monthlyChange, trend.trend.status != .insufficientData,
                  let details = info(trend.key) else { continue }
            for region in details.primaryRegions {
                changes[region, default: []].append(monthly)
            }
        }
        return changes
            .map { region, values in
                StrengthTrend(region: region, change: values.reduce(0, +) / Double(values.count), exercises: values.count)
            }
            .sorted { $0.change != $1.change ? $0.change > $1.change : $0.region < $1.region }
    }

    // MARK: Pomoćno

    private func interval(of size: BucketSize, containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: size == .week ? .weekOfYear : .month, for: date)
    }

    private func bucketStarts(size: BucketSize, count: Int, now: Date, calendar: Calendar) -> [Date] {
        guard count > 0, var current = interval(of: size, containing: now, calendar: calendar)?.start else { return [] }
        var starts = [current]
        let unit: Calendar.Component = size == .week ? .weekOfYear : .month
        while starts.count < count, let previous = calendar.date(byAdding: unit, value: -1, to: current) {
            current = interval(of: size, containing: previous, calendar: calendar)?.start ?? previous
            starts.insert(current, at: 0)
        }
        return starts
    }
}
