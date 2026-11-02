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

    public init(
        primary: [Muscle] = [], secondary: [Muscle] = [], primaryRegions: [String] = [], secondaryRegions: [String] = []
    ) {
        self.primary = primary
        self.secondary = secondary
        self.primaryRegions = primaryRegions
        self.secondaryRegions = secondaryRegions
    }
}

/// Daje podatke o vježbi prema `ExerciseRef.key`.
public typealias ExerciseInfoProvider = (String) -> ExerciseInfo?

public struct ExercisePoint: Equatable, Sendable {
    public let date: Date
    /// Najveća težina radne serije (kg); 0 kad vježba nema težinu.
    public let bestWeightKg: Double
    public let bestReps: Int
    public let estimatedOneRepMaxKg: Double?
    public let volumeKg: Double
}

public struct MuscleLoad: Equatable, Sendable {
    public var volumeKg: Double
    public var sets: Int
}

public enum BucketSize: Sendable {
    case week
    case month
}

public struct VolumeBucket: Equatable, Sendable {
    public let start: Date
    public var loads: [Muscle: MuscleLoad]

    public var totalVolumeKg: Double { loads.values.reduce(0) { $0 + $1.volumeKg } }
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
    /// Broj treninga koji su opteretili regiju.
    public var sessions: Int
    public var volumeKg: Double
    /// Relativno opterećenje 0...1 prema najopterećenijoj regiji (za boju heatmapa).
    public var intensity: Double
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
            guard let session = exercise.session, session.state == .finished else { continue }
            let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values).filter { $0.kind == .working }
            guard !sets.isEmpty else { continue }
            let type = exercise.inputType
            var bestWeight = 0.0
            var bestReps = 0
            var oneRepMax: Double?
            for set in sets {
                let weight = (type == .weightedBodyweight ? set.extraWeightKg : set.weightKg) ?? 0
                bestWeight = max(bestWeight, weight)
                bestReps = max(bestReps, set.reps ?? 0)
                if type == .weightReps || type == .weightedBodyweight,
                   let estimate = SetMetrics.estimatedOneRepMax(weightKg: weight, reps: set.reps ?? 0, formula: formula) {
                    oneRepMax = max(oneRepMax ?? 0, estimate)
                }
            }
            let volume = sets.reduce(0) { $0 + SetMetrics.volume($1, inputType: type) }
            points.append(ExercisePoint(
                date: session.startedAt, bestWeightKg: bestWeight, bestReps: bestReps,
                estimatedOneRepMaxKg: oneRepMax, volumeKg: volume
            ))
        }
        return points.sorted { $0.date < $1.date }
    }

    // MARK: Volumen po mišićnoj skupini

    /// Volumen i broj radnih serija po primarnom mišiću, za `count` tjedana ili mjeseci koji završavaju
    /// onim koji sadrži `now` (od najstarijeg prema najnovijem).
    public func volumeBuckets(
        size: BucketSize, count: Int, endingAt now: Date = Date(), calendar: Calendar = .current,
        info: ExerciseInfoProvider
    ) throws -> [VolumeBucket] {
        let starts = bucketStarts(size: size, count: count, now: now, calendar: calendar)
        guard let first = starts.first, let last = starts.last,
              let end = interval(of: size, containing: last, calendar: calendar)?.end else { return [] }
        var buckets = Dictionary(uniqueKeysWithValues: starts.map { ($0, VolumeBucket(start: $0, loads: [:])) })

        for session in try GymQueries(context: context).finishedSessions(from: first, to: end) {
            guard let start = interval(of: size, containing: session.startedAt, calendar: calendar)?.start,
                  buckets[start] != nil else { continue }
            for exercise in session.orderedExercises where !exercise.isRemoved {
                guard let muscles = info(exercise.exerciseKey)?.primary, !muscles.isEmpty else { continue }
                let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values).filter { $0.kind == .working }
                let volume = sets.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
                for muscle in muscles {
                    var load = buckets[start]?.loads[muscle] ?? MuscleLoad(volumeKg: 0, sets: 0)
                    load.volumeKg += volume
                    load.sets += sets.count
                    buckets[start]?.loads[muscle] = load
                }
            }
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
    public func personalRecords(kinds: Set<PRKind> = Set(PRKind.allCases)) throws -> [RecordEntry] {
        let finished = SessionState.finished.rawValue
        let sessions = try context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished },
            sortBy: [SortDescriptor(\.startedAt)]
        ))
        var history: [String: [[SetValues]]] = [:]
        var entries: [RecordEntry] = []
        for session in sessions {
            for exercise in session.orderedExercises where !exercise.isRemoved {
                let done = exercise.orderedSets.filter(\.isCompleted).map(\.values)
                guard !done.isEmpty else { continue }
                let key = exercise.exerciseKey
                let found = PersonalRecordDetector.records(
                    current: done, history: history[key] ?? [], inputType: exercise.inputType, kinds: kinds
                )
                for record in found {
                    entries.append(RecordEntry(
                        date: session.startedAt, exerciseKey: key, exerciseName: exercise.exerciseName, record: record
                    ))
                }
                history[key, default: []].append(done)
            }
        }
        return entries.reversed()
    }

    // MARK: Body heatmap

    /// Opterećenje po regiji tijela u razdoblju. Primarne regije računaju puni volumen, sekundarne pola.
    public func heatmap(from start: Date, until end: Date, info: ExerciseInfoProvider) throws -> [String: RegionLoad] {
        var result: [String: RegionLoad] = [:]
        for session in try GymQueries(context: context).finishedSessions(from: start, to: end) {
            var touched = Set<String>()
            for exercise in session.orderedExercises where !exercise.isRemoved {
                guard let details = info(exercise.exerciseKey) else { continue }
                let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values).filter { $0.kind == .working }
                guard !sets.isEmpty else { continue }
                let volume = sets.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
                for (regions, weight) in [(details.primaryRegions, 1.0), (details.secondaryRegions, 0.5)] {
                    for region in regions {
                        var load = result[region] ?? RegionLoad(sessions: 0, volumeKg: 0, intensity: 0)
                        load.volumeKg += volume * weight
                        if touched.insert(region).inserted { load.sessions += 1 }
                        result[region] = load
                    }
                }
            }
        }
        let peak = result.values.map(\.sessions).max() ?? 0
        guard peak > 0 else { return result }
        for (region, load) in result {
            result[region]?.intensity = Double(load.sessions) / Double(peak)
        }
        return result
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
