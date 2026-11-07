import Catalog
import Foundation
import Models
import SwiftData
import Training

/// Trend jedne vježbe s podacima za prikaz i prijedloge.
public struct ExerciseTrendEntry: Equatable, Sendable {
    public let key: String
    public let name: String
    public let measure: TrendMeasure
    public let trend: ExerciseTrend
    public let primaryRegions: [String]
}

/// Najteža serija s barem toliko ponavljanja (tablica rekorda po ponavljanjima).
public struct RepMaxEntry: Equatable, Sendable {
    public let reps: Int
    public let weightKg: Double
    public let date: Date
}

/// Raspodjela radnih serija po ponavljanjima u rezervi (RIR 0, 1, 2, 3, 4 i više).
public struct EffortDistribution: Equatable, Sendable {
    /// Pet brojeva: RIR 0, 1, 2, 3, 4+.
    public var counts: [Int] = Array(repeating: 0, count: 5)
    /// Radne serije bez upisanog RPE-a.
    public var unrated = 0

    public var rated: Int { counts.reduce(0, +) }
}

/// Raspodjela radnih serija po težini u odnosu na najbolju procjenu 1RM vježbe.
public struct IntensityDistribution: Equatable, Sendable {
    /// Granice zona (udio 1RM): ispod 60 %, 60 do 75 %, 75 do 85 %, iznad 85 %.
    public static let bounds = [0.60, 0.75, 0.85]
    public var counts: [Int] = Array(repeating: 0, count: 4)

    public var total: Int { counts.reduce(0, +) }

    public static func zone(of share: Double) -> Int {
        bounds.firstIndex { share < $0 } ?? bounds.count
    }
}

extension StatisticsEngine {

    // MARK: Trend i status vježbi

    /// Trend svake vježbe rađene u zadnjih `weeks` tjedana do `now`, abecedno.
    public func exerciseTrends(
        weeks: Int = TrendAnalysis.windowWeeks, endingAt now: Date = Date(), info: ExerciseInfoProvider,
        formula: SetMetrics.OneRepMaxFormula = .epley
    ) throws -> [ExerciseTrendEntry] {
        let from = now.addingTimeInterval(-Double(weeks) * 7 * 24 * 3600)
        var points: [String: [ExercisePoint]] = [:]
        var names: [String: String] = [:]
        for session in try GymQueries(context: context).finishedSessions(from: from, to: now.addingTimeInterval(1)) {
            for exercise in session.orderedExercises where !exercise.isRemoved && !exercise.exerciseKey.isEmpty {
                guard let point = Self.point(of: exercise, date: session.startedAt, formula: formula) else { continue }
                points[exercise.exerciseKey, default: []].append(point)
                names[exercise.exerciseKey] = names[exercise.exerciseKey] ?? exercise.exerciseName
            }
        }
        return points.compactMap { key, progress in
            entry(key: key, name: names[key] ?? "", progress: progress, now: now, weeks: weeks, info: info)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Trend jedne vježbe u zadnjih `weeks` tjedana. Nil za vrste bez mjerljivog napretka (trajanje, udaljenost).
    public func exerciseTrend(
        of ref: ExerciseRef, weeks: Int = TrendAnalysis.windowWeeks, endingAt now: Date = Date(),
        info: ExerciseInfoProvider, formula: SetMetrics.OneRepMaxFormula = .epley
    ) throws -> ExerciseTrendEntry? {
        entry(key: ref.key, name: ref.name, progress: try progress(of: ref, formula: formula), now: now, weeks: weeks, info: info)
    }

    private func entry(
        key: String, name: String, progress: [ExercisePoint], now: Date, weeks: Int, info: ExerciseInfoProvider
    ) -> ExerciseTrendEntry? {
        guard let source = TrendAnalysis.points(from: progress) else { return nil }
        let details = info(key)
        let trend = TrendAnalysis.trend(
            of: source.points, endingAt: now, windowWeeks: weeks,
            defaultNoise: TrendAnalysis.defaultNoise(isCompound: details?.isCompound, measure: source.measure)
        )
        return ExerciseTrendEntry(
            key: key, name: name, measure: source.measure, trend: trend, primaryRegions: details?.primaryRegions ?? []
        )
    }

    // MARK: Tablica rekorda po ponavljanjima

    /// Najteža serija za svaki raspon ponavljanja (`PersonalRecordDetector.repRanges`): s barem toliko ponavljanja.
    public func repMaxTable(of ref: ExerciseRef) throws -> [RepMaxEntry] {
        let key = ref.key
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        var best: [Int: RepMaxEntry] = [:]
        for exercise in try context.fetch(descriptor) {
            guard let session = exercise.session, session.state == .finished else { continue }
            for set in exercise.orderedSets where set.isCompleted && set.kind == .working {
                let values = set.values
                guard let load = SetMetrics.load(values, inputType: exercise.inputType), load > 0, let reps = values.reps else { continue }
                for range in PersonalRecordDetector.repRanges where reps >= range {
                    if load > (best[range]?.weightKg ?? 0) {
                        best[range] = RepMaxEntry(reps: range, weightKg: load, date: session.startedAt)
                    }
                }
            }
        }
        return PersonalRecordDetector.repRanges.compactMap { best[$0] }
    }

    // MARK: Napor i intenzitet

    /// Radne serije u razdoblju po ponavljanjima u rezervi (iz upisanog RPE-a).
    public func effortDistribution(from start: Date, until end: Date) throws -> EffortDistribution {
        var result = EffortDistribution()
        for session in try GymQueries(context: context).finishedSessions(from: start, to: end) {
            for exercise in session.orderedExercises where !exercise.isRemoved {
                for set in exercise.orderedSets where set.isCompleted && set.kind == .working {
                    guard let rpe = set.rpe else {
                        result.unrated += 1
                        continue
                    }
                    let rir = Int(max(0, 10 - rpe).rounded(.down))
                    result.counts[min(rir, 4)] += 1
                }
            }
        }
        return result
    }

    /// Radne serije s teretom u razdoblju po udjelu najbolje procjene 1RM vježbe. Najbolja procjena gleda se
    /// u razdoblju i 8 tjedana prije njega, da prvi tjedni razdoblja imaju s čime se usporediti.
    public func intensityDistribution(
        from start: Date, until end: Date, formula: SetMetrics.OneRepMaxFormula = .epley
    ) throws -> IntensityDistribution {
        let lookBack = start.addingTimeInterval(-8 * 7 * 24 * 3600)
        let sessions = try GymQueries(context: context).finishedSessions(from: lookBack, to: end)
        var reference: [String: Double] = [:]
        for session in sessions {
            for exercise in session.orderedExercises where !exercise.isRemoved {
                for set in exercise.orderedSets where set.isCompleted {
                    if let estimate = SetMetrics.strengthEstimate(set.values, inputType: exercise.inputType, formula: formula) {
                        reference[exercise.exerciseKey] = max(reference[exercise.exerciseKey] ?? 0, estimate)
                    }
                }
            }
        }
        var result = IntensityDistribution()
        for session in sessions where session.startedAt >= start {
            for exercise in session.orderedExercises where !exercise.isRemoved {
                guard let best = reference[exercise.exerciseKey], best > 0 else { continue }
                for set in exercise.orderedSets where set.isCompleted && set.kind == .working {
                    guard let load = SetMetrics.load(set.values, inputType: exercise.inputType), load > 0 else { continue }
                    result.counts[IntensityDistribution.zone(of: load / best)] += 1
                }
            }
        }
        return result
    }
}
