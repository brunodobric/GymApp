import Foundation
import Models
import SwiftData
import Training

/// Razdoblje pregleda u Statistici: kalendarski tjedan, mjesec ili godina.
public enum OverviewPeriod: String, CaseIterable, Sendable {
    case week
    case month
    case year

    public var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// Razdoblje koje sadrži `date` (tjedan počinje prema kalendaru, npr. ponedjeljkom).
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    /// Datum pomaknut za `value` razdoblja (-1 prethodno, 1 sljedeće).
    public func shift(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }
}

/// Brojke jednog tjedna, mjeseca ili godine za ekran Pregled: treninzi, vrijeme, tvrde serije, kardio,
/// dani s vrstom treninga i (za godinu) treninzi po mjesecima.
public struct PeriodSummary: Equatable, Sendable {
    /// Jedan mjesec godine za stupce.
    public struct Month: Equatable, Sendable {
        public let start: Date
        public var sessions = 0
        public var hardSets = 0
    }

    public let period: OverviewPeriod
    public let interval: DateInterval
    /// Svi dani razdoblja, od prvog.
    public var days: [WeekProgress.Day]
    /// Dvanaest mjeseci za godinu; prazno za tjedan i mjesec.
    public var months: [Month]
    public var sessions = 0
    /// Tvrde serije snage (`SetMetrics.isHard`); kardio vježbe se ne broje.
    public var hardSets = 0
    public var cardioSeconds = 0
    public var cardioMeters: Double = 0
    public var totalSeconds: TimeInterval = 0
    /// Planirani treninzi tjedno (dani tjedno iz onboardinga); nil bez plana.
    public let weeklyGoal: Int?
    /// Tjedni za prosjek (`PeriodSummary.weeks`).
    public let weeks: Double

    public var trainedDays: Int { days.filter(\.isTrained).count }
    public var sessionsPerWeek: Double { Double(sessions) / max(weeks, 1) }

    /// Tjedni razdoblja za tjedni prosjek, najmanje 1. Tekuće razdoblje broji se do `now`, a razdoblje
    /// u kojem je korisnik počeo od prvog treninga (`since`), da prosjek ne bude razvodnjen.
    public static func weeks(in interval: DateInterval, now: Date, since: Date?) -> Double {
        let from = max(interval.start, since ?? interval.start)
        let to = min(interval.end, max(now, from))
        return max(1, to.timeIntervalSince(from) / (7 * 86_400))
    }

    /// Sažetak razdoblja koje sadrži `date` iz završenih treninga; treninzi izvan razdoblja se preskaču.
    public static func make(
        sessions all: [Session], period: OverviewPeriod, containing date: Date, now: Date = Date(),
        since: Date? = nil, goal: Int?, calendar: Calendar = .current, isCardio: (String) -> Bool
    ) -> PeriodSummary {
        let interval = period.interval(containing: date, calendar: calendar)
        var days: [WeekProgress.Day] = []
        var cursor = interval.start
        while cursor < interval.end {
            days.append(WeekProgress.Day(date: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        var months: [Month] = []
        if period == .year {
            for index in 0..<12 {
                if let start = calendar.date(byAdding: .month, value: index, to: interval.start) {
                    months.append(Month(start: start))
                }
            }
        }
        var summary = PeriodSummary(
            period: period, interval: interval, days: days, months: months,
            weeklyGoal: goal.flatMap { $0 > 0 ? $0 : nil },
            weeks: weeks(in: interval, now: now, since: since)
        )
        let dayIndex = Dictionary(days.indices.map { (days[$0].date, $0) }, uniquingKeysWith: { first, _ in first })

        for session in all where session.state == .finished && interval.contains(session.startedAt)
            && session.startedAt < interval.end {
            summary.sessions += 1
            let figures = SessionFigures(session: session, isCardio: isCardio)
            summary.totalSeconds += figures.durationSeconds
            summary.hardSets += figures.hardSets
            summary.cardioSeconds += figures.cardioSeconds
            summary.cardioMeters += figures.cardioMeters ?? 0
            let mix = SessionCardio.mix(of: session, isCardio: isCardio)
            if let index = dayIndex[calendar.startOfDay(for: session.startedAt)] {
                if mix.kinds.contains(.strength) { summary.days[index].strength = true }
                if mix.kinds.contains(.cardio) { summary.days[index].cardio = true }
            }
            if period == .year {
                let month = calendar.component(.month, from: session.startedAt) - 1
                if summary.months.indices.contains(month) {
                    summary.months[month].sessions += 1
                    summary.months[month].hardSets += figures.hardSets
                }
            }
        }
        return summary
    }

    /// Treninzi po danu (ključ je početak dana), svaki dan od ranijeg prema kasnijem.
    /// Nezavršeni treninzi i treninzi izvan razdoblja se preskaču.
    public func sessionsByDay(_ sessions: [Session], calendar: Calendar = .current) -> [Date: [Session]] {
        let sorted = sessions
            .filter { $0.state == .finished && interval.contains($0.startedAt) && $0.startedAt < interval.end }
            .sorted { $0.startedAt < $1.startedAt }
        return Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.startedAt) }
    }
}

extension VolumeBucket {
    /// Serije i tonaža po regiji podijeljene s brojem tjedana, za usporedbu mjeseca ili godine
    /// sa zonama serija tjedno. Ukupni zbrojevi ostaju.
    public func perWeek(_ weeks: Double) -> VolumeBucket {
        let divisor = max(weeks, 1)
        var result = self
        for (region, load) in loads {
            result.loads[region] = MuscleLoad(volumeKg: load.volumeKg / divisor, sets: load.sets / divisor)
        }
        return result
    }
}

extension StatisticsEngine {
    /// Početak prvog završenog treninga u aplikaciji; nil bez treninga.
    public func firstSessionDate() throws -> Date? {
        let finished = SessionState.finished.rawValue
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.startedAt
    }

    /// Sažetak tjedna, mjeseca ili godine koji sadrži `date`, iz vlastitih treninga i treninga iz Zdravlja.
    public func periodSummary(
        _ period: OverviewPeriod, containing date: Date, now: Date = Date(), goal: Int?,
        calendar: Calendar = .current, isCardio: (String) -> Bool
    ) throws -> PeriodSummary {
        let interval = period.interval(containing: date, calendar: calendar)
        return PeriodSummary.make(
            sessions: try sessions(in: interval), period: period, containing: date, now: now,
            since: try firstSessionDate(), goal: goal, calendar: calendar, isCardio: isCardio
        )
    }

    /// Završeni treninzi u razdoblju (vlastiti i iz Zdravlja).
    public func sessions(in interval: DateInterval) throws -> [Session] {
        try GymQueries(context: context).finishedSessions(from: interval.start, to: interval.end)
    }

    /// Tvrde serije i tonaža po regiji u razdoblju (kao jedan `volumeBuckets` stupac).
    public func volumeBucket(in interval: DateInterval, info: ExerciseInfoProvider) throws -> VolumeBucket {
        var bucket = VolumeBucket(start: interval.start)
        for session in try sessions(in: interval) {
            bucket.add(session, info: info)
        }
        return bucket
    }

    /// Serije po mišiću u razdoblju koje sadrži `date` i u razdoblju prije. Tjedan se uspoređuje u ukupnim
    /// serijama, a mjesec i godina u prosjeku serija tjedno, jer su različite duljine.
    public func periodVolume(
        _ period: OverviewPeriod, containing date: Date, now: Date = Date(), calendar: Calendar = .current,
        info: ExerciseInfoProvider
    ) throws -> VolumeComparison? {
        let current = period.interval(containing: date, calendar: calendar)
        let previous = period.interval(containing: period.shift(current.start, by: -1, calendar: calendar), calendar: calendar)
        var buckets = [try volumeBucket(in: previous, info: info), try volumeBucket(in: current, info: info)]
        if period != .week {
            let since = try firstSessionDate()
            buckets = [
                buckets[0].perWeek(PeriodSummary.weeks(in: previous, now: now, since: since)),
                buckets[1].perWeek(PeriodSummary.weeks(in: current, now: now, since: since)),
            ]
        }
        return VolumeComparison(buckets: buckets)
    }
}
