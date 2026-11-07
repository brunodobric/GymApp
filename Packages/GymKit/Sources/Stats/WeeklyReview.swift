import Catalog
import Foundation
import Models
import SwiftData
import Training

/// Ocjena jednog dijela tjednog pregleda.
public enum ReviewLevel: String, Sendable {
    case good
    case fair
    case attention
    case noData
}

/// Tjedni pregled od četiri dijela, svaki s vlastitim uporištem u istraživanjima. Namjerno nema jedne složene
/// ocjene: zbroj "dobrih" dijelova (`goodCount`) je jedina brojka i nema skrivenih težina.
public struct WeeklyReview: Equatable, Sendable {
    /// Trend snage vježbi (`TrendAnalysis`).
    public struct Strength: Equatable, Sendable {
        public var level: ReviewLevel
        public var improving = 0
        public var stable = 0
        public var plateau = 0
        public var declining = 0
        /// Medijan mjesečne promjene vježbi s dovoljno podataka.
        public var medianMonthlyChange: Double?
    }

    /// Glavni mišići u zoni tvrdih serija tjedno za cilj (Pelland i sur. 2024, Schoenfeld i sur. 2017).
    public struct Volume: Equatable, Sendable {
        public var level: ReviewLevel
        public var inZone = 0
        public var regions = 0
        public var zone: ClosedRange<Double>
    }

    /// Odrađeni treninzi prema planiranima.
    public struct Consistency: Equatable, Sendable {
        public var level: ReviewLevel
        public var sessions = 0
        public var weeks: Double = 1
        /// Planirani treninzi u razdoblju (dani tjedno iz onboardinga × tjedni). Nil bez plana.
        public var planned: Int?

        public var sessionsPerWeek: Double { Double(sessions) / max(weeks, 1) }
        public var ratio: Double? { planned.map { $0 > 0 ? Double(sessions) / Double($0) : 0 } }
    }

    /// Udio radnih serija blizu otkaza (RIR 0 do 3) kad korisnik upisuje RPE (Robinson i sur. 2024).
    public struct Effort: Equatable, Sendable {
        public var level: ReviewLevel
        public var ratedSets = 0
        public var closeToFailureShare: Double?
    }

    public var strength: Strength
    public var volume: Volume
    public var consistency: Consistency
    public var effort: Effort

    public var levels: [ReviewLevel] { [strength.level, volume.level, consistency.level, effort.level] }
    public var goodCount: Int { levels.filter { $0 == .good }.count }
    /// Dijelovi s podacima.
    public var ratedCount: Int { levels.filter { $0 != .noData }.count }
}

public enum WeeklyReviewBuilder {
    /// Razdoblje pregleda u tjednima.
    public static let weeks = 4
    /// Najmanje ocijenjenih serija za dio "napor".
    public static let minimumRatedSets = 10

    /// Zona tvrdih serija tjedno po glavnom mišiću prema cilju iz onboardinga.
    public static func volumeZone(for goal: TrainingGoal?) -> ClosedRange<Double> {
        switch goal {
        case .strength: 4...30
        case .recomposition, .generalFitness: 5...30
        case .hypertrophy, nil: 10...20
        }
    }

    private static func level(_ share: Double, good: Double, fair: Double) -> ReviewLevel {
        share >= good ? .good : share >= fair ? .fair : .attention
    }

    public static func strength(_ trends: [ExerciseTrendEntry]) -> WeeklyReview.Strength {
        var result = WeeklyReview.Strength(level: .noData)
        var changes: [Double] = []
        for entry in trends {
            switch entry.trend.status {
            case .improving: result.improving += 1
            case .stable: result.stable += 1
            case .plateau: result.plateau += 1
            case .declining: result.declining += 1
            case .insufficientData: continue
            }
            if let change = entry.trend.monthlyChange { changes.append(change) }
        }
        let rated = result.improving + result.stable + result.plateau + result.declining
        guard rated > 0 else { return result }
        result.medianMonthlyChange = TrendAnalysis.median(changes)
        result.level = level(Double(result.improving + result.stable) / Double(rated), good: 0.75, fair: 0.5)
        return result
    }

    /// `weeklySets`: prosjek tvrdih serija tjedno po regiji (`RegionLoad.weeklySets`).
    public static func volume(weeklySets: [String: Double], goal: TrainingGoal?) -> WeeklyReview.Volume {
        let zone = volumeZone(for: goal)
        var result = WeeklyReview.Volume(level: .noData, regions: BodyRegion.major.count, zone: zone)
        guard weeklySets.values.contains(where: { $0 > 0 }) else { return result }
        result.inZone = BodyRegion.major.filter { zone.contains(weeklySets[$0] ?? 0) }.count
        result.level = level(Double(result.inZone) / Double(result.regions), good: 0.7, fair: 0.4)
        return result
    }

    public static func consistency(sessions: Int, weeks: Double, plannedPerWeek: Int?) -> WeeklyReview.Consistency {
        var result = WeeklyReview.Consistency(level: .attention, sessions: sessions, weeks: max(weeks, 1))
        if let plannedPerWeek, plannedPerWeek > 0 {
            let planned = Int((Double(plannedPerWeek) * result.weeks).rounded())
            result.planned = planned
            result.level = level(Double(sessions) / Double(max(planned, 1)), good: 0.9, fair: 0.6)
        } else {
            let perWeek = result.sessionsPerWeek
            result.level = perWeek >= 2 ? .good : perWeek >= 1 ? .fair : .attention
        }
        return result
    }

    /// `rpes`: upisani RPE radnih serija u razdoblju.
    public static func effort(rpes: [Double]) -> WeeklyReview.Effort {
        var result = WeeklyReview.Effort(level: .noData, ratedSets: rpes.count)
        guard rpes.count >= minimumRatedSets else { return result }
        // RIR 0 do 3 = RPE 7 i više.
        let share = Double(rpes.filter { $0 >= 7 }.count) / Double(rpes.count)
        result.closeToFailureShare = share
        result.level = level(share, good: 0.7, fair: 0.4)
        return result
    }
}

// MARK: - Prijedlozi

/// Prijedlog za dalje. Svaki ima uvjet i izvor (`docs/SPECIFIKACIJA.md`); tekst daje sučelje.
public enum Suggestion: Equatable, Sendable {
    /// Više vježbi pada: lakši tjedan (Bell i sur. 2023).
    case deload(exercises: Int)
    /// Odrađeno manje od 60 % planiranih treninga: raspored s manje dana.
    case fewerDays(sessionsPerWeek: Double, planned: Int)
    /// Vježba je na platou, a mišić ima manje od 10 serija tjedno (doza i odgovor, Pelland i sur. 2024).
    case addSets(region: String, exerciseName: String)
    /// Vježba je na platou, a mišić ima više od 20 serija tjedno: manje volumena ili lakši tjedan.
    case reduceVolume(region: String, exerciseName: String)
    /// Tri izvođenja zaredom s RIR 4 i više uz istu težinu: veća težina (dvostruka progresija, Helms i sur. 2016).
    case increaseLoad(exerciseName: String)
    /// Glavni mišić nije rađen 14 i više dana, a ranije jest.
    case missedMuscle(region: String, days: Int)
}

public struct SuggestionInput: Sendable {
    public var trends: [ExerciseTrendEntry]
    /// Prosjek tvrdih serija tjedno po regiji u zadnja 4 tjedna.
    public var weeklySets: [String: Double]
    /// Zadnji trening po regiji u zadnjih 8 tjedana.
    public var lastTrained: [String: Date]
    public var consistency: WeeklyReview.Consistency
    public var goal: TrainingGoal?
    /// Vježbe s tri lagana izvođenja zaredom uz istu težinu.
    public var easyExercises: [String]
    public var now: Date

    public init(
        trends: [ExerciseTrendEntry], weeklySets: [String: Double], lastTrained: [String: Date],
        consistency: WeeklyReview.Consistency, goal: TrainingGoal?, easyExercises: [String], now: Date
    ) {
        self.trends = trends
        self.weeklySets = weeklySets
        self.lastTrained = lastTrained
        self.consistency = consistency
        self.goal = goal
        self.easyExercises = easyExercises
        self.now = now
    }
}

public enum SuggestionEngine {
    public static let missedMuscleDays = 14

    /// Prijedlozi od najvažnijeg. Svaki mišić dobiva najviše jedan prijedlog o volumenu.
    public static func suggestions(_ input: SuggestionInput) -> [Suggestion] {
        var result: [Suggestion] = []
        let declining = input.trends.filter { $0.trend.status == .declining }.count
        if declining >= 2 { result.append(.deload(exercises: declining)) }
        if let planned = input.consistency.planned, let ratio = input.consistency.ratio, ratio < 0.6 {
            result.append(.fewerDays(sessionsPerWeek: input.consistency.sessionsPerWeek, planned: planned))
        }

        let growthGoal = input.goal == nil || input.goal == .hypertrophy || input.goal == .strength
        var handled = Set<String>()
        for entry in input.trends where entry.trend.status == .plateau {
            guard let region = entry.primaryRegions.first, !handled.contains(region) else { continue }
            let sets = input.weeklySets[region] ?? 0
            if sets < 10, growthGoal {
                result.append(.addSets(region: region, exerciseName: entry.name))
                handled.insert(region)
            } else if sets > 20 {
                result.append(.reduceVolume(region: region, exerciseName: entry.name))
                handled.insert(region)
            }
        }
        result += input.easyExercises.map { .increaseLoad(exerciseName: $0) }

        let day: TimeInterval = 24 * 3600
        for region in BodyRegion.major {
            guard let last = input.lastTrained[region] else { continue }
            let days = Int(input.now.timeIntervalSince(last) / day)
            if days >= missedMuscleDays { result.append(.missedMuscle(region: region, days: days)) }
        }
        return result
    }
}

// MARK: - Izračun iz baze

extension StatisticsEngine {

    /// Tjedni pregled i prijedlozi za zadnja 4 tjedna do `now`.
    public func weeklyReview(
        endingAt now: Date = Date(), goal: TrainingGoal?, plannedPerWeek: Int?, info: ExerciseInfoProvider
    ) throws -> (review: WeeklyReview, suggestions: [Suggestion]) {
        let day: TimeInterval = 24 * 3600
        let end = now.addingTimeInterval(1)
        let start = now.addingTimeInterval(-Double(WeeklyReviewBuilder.weeks) * 7 * day)
        let trends = try exerciseTrends(endingAt: now, info: info)
        let loads = try heatmap(from: start, until: end, info: info)
        let weeklySets = loads.mapValues(\.weeklySets)
        let sessions = try GymQueries(context: context).finishedSessions(from: start, to: end)
        let own = sessions.filter { !$0.isImportedFromWorkoutsApp }
        let rpes = own.flatMap { session in
            session.orderedExercises.filter { !$0.isRemoved }.flatMap { exercise in
                exercise.orderedSets.filter { $0.isCompleted && $0.kind == .working }.compactMap(\.rpe)
            }
        }
        let weeks = min(Double(WeeklyReviewBuilder.weeks), try weeksCovered(from: start, until: end))
        let consistency = WeeklyReviewBuilder.consistency(sessions: sessions.count, weeks: weeks, plannedPerWeek: plannedPerWeek)
        let review = WeeklyReview(
            strength: WeeklyReviewBuilder.strength(trends),
            volume: WeeklyReviewBuilder.volume(weeklySets: weeklySets, goal: goal),
            consistency: consistency,
            effort: WeeklyReviewBuilder.effort(rpes: rpes)
        )
        let earlier = try heatmap(from: now.addingTimeInterval(-8 * 7 * day), until: end, info: info)
        let input = SuggestionInput(
            trends: trends, weeklySets: weeklySets, lastTrained: earlier.compactMapValues(\.lastTrained),
            consistency: consistency, goal: goal, easyExercises: try easyExercises(endingAt: now), now: now
        )
        return (review, SuggestionEngine.suggestions(input))
    }

    /// Vježbe čija su zadnja tri izvođenja (u 8 tjedana) bila lagana: sve radne serije s RIR 4 i više
    /// (RPE 6 i manje) i ista najveća težina.
    public func easyExercises(endingAt now: Date = Date()) throws -> [String] {
        let start = now.addingTimeInterval(-8 * 7 * 24 * 3600)
        var performances: [String: [(name: String, load: Double, easy: Bool)]] = [:]
        // Od najnovijeg prema starijem.
        for session in try GymQueries(context: context).finishedSessions(from: start, to: now.addingTimeInterval(1)) {
            for exercise in session.orderedExercises where !exercise.isRemoved {
                let working = exercise.orderedSets.filter { $0.isCompleted && $0.kind == .working }.map(\.values)
                guard !working.isEmpty else { continue }
                let load = working.compactMap { SetMetrics.load($0, inputType: exercise.inputType) }.max() ?? 0
                let easy = load > 0 && working.allSatisfy { ($0.rpe ?? 10) <= 6 }
                performances[exercise.exerciseKey, default: []].append((exercise.exerciseName, load, easy))
            }
        }
        return performances.values.compactMap { list -> String? in
            let last = list.prefix(3)
            guard last.count == 3, last.allSatisfy({ $0.easy }), Set(last.map { $0.load }).count == 1 else { return nil }
            return last.first?.name
        }
        .sorted()
    }
}
