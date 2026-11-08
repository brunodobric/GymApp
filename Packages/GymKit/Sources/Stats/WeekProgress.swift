import Foundation
import Models
import SwiftData
import Training

/// Tekući tjedan za karticu Ovaj tjedan na Početnoj: odrađeni treninzi prema cilju iz onboardinga,
/// dani s vrstom treninga, tvrde serije, minute kardija, ukupno vrijeme i niz tjedana s ispunjenim ciljem.
public struct WeekProgress: Equatable, Sendable {
    /// Jedan dan tjedna i vrste treninga odrađene tog dana.
    public struct Day: Equatable, Sendable {
        public let date: Date
        public var strength = false
        public var cardio = false

        public var isTrained: Bool { strength || cardio }

        /// Vrsta za prikaz (ikona dana); nil za dan bez treninga.
        public var mix: SessionMix? {
            switch (strength, cardio) {
            case (true, true): .mixed
            case (true, false): .strength
            case (false, true): .cardio
            case (false, false): nil
            }
        }
    }

    /// Početak tjedna (prema kalendaru, npr. ponedjeljak).
    public let start: Date
    /// Sedam dana tjedna, od prvog.
    public var days: [Day]
    /// Odrađeni treninzi u tjednu (i kardio iz Zdravlja).
    public var sessions = 0
    /// Planirani treninzi tjedno (dani tjedno iz onboardinga); nil bez plana.
    public let goal: Int?
    /// Tvrde serije snage (`SetMetrics.isHard`); kardio vježbe se ne broje.
    public var hardSets = 0
    /// Vrijeme kardija: kardio treninzi cijeli, a u treningu snage odrađene kardio vježbe.
    public var cardioSeconds = 0
    /// Udaljenost kardija u metrima (kardio iz Zdravlja i kardio vježbe s udaljenošću).
    public var cardioMeters: Double = 0
    /// Zbroj trajanja svih treninga.
    public var totalSeconds: TimeInterval = 0
    /// Uzastopni tjedni s ispunjenim ciljem (bez cilja: s barem jednim treningom), do prošlog tjedna,
    /// i ovaj tjedan ako je cilj već ispunjen.
    public var streakWeeks = 0

    /// Udio cilja (0 do 1) za traku; nil bez cilja.
    public var goalFraction: Double? {
        guard let goal, goal > 0 else { return nil }
        return min(Double(sessions) / Double(goal), 1)
    }

    /// Koliko treninga tjedno treba za tjedan koji se broji u niz.
    var weeklyTarget: Int { max(goal ?? 1, 1) }

    /// Najviše tjedana unatrag koji se gledaju za niz.
    public static let streakLimit = 52

    /// Sažetak tjedna koji sadrži `now` iz završenih treninga. `sessions` smije sadržavati i starije treninge
    /// (za niz tjedana); treninzi nakon kraja tjedna se ne broje.
    public static func make(
        sessions all: [Session], now: Date, goal: Int?, calendar: Calendar = .current,
        isCardio: (String) -> Bool
    ) -> WeekProgress {
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 86_400)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }.map { Day(date: $0) }
        var progress = WeekProgress(start: week.start, days: days, goal: goal.flatMap { $0 > 0 ? $0 : nil })
        let finished = all.filter { $0.state == .finished && $0.startedAt < week.end }

        for session in finished where session.startedAt >= week.start {
            progress.sessions += 1
            let figures = SessionFigures(session: session, isCardio: isCardio)
            progress.totalSeconds += figures.durationSeconds
            progress.hardSets += figures.hardSets
            progress.cardioSeconds += figures.cardioSeconds
            progress.cardioMeters += figures.cardioMeters ?? 0
            let mix = SessionCardio.mix(of: session, isCardio: isCardio)
            if let index = progress.days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: session.startedAt) }) {
                if mix.kinds.contains(.strength) { progress.days[index].strength = true }
                if mix.kinds.contains(.cardio) { progress.days[index].cardio = true }
            }
        }
        progress.streakWeeks = streak(of: finished, before: week.start, current: progress.sessions,
                                      target: progress.weeklyTarget, calendar: calendar)
        return progress
    }

    /// Treninzi po danima tjedna (poravnato s `days`), svaki dan od ranijeg prema kasnijem.
    /// Nezavršeni treninzi i treninzi izvan tjedna se preskaču.
    public func sessionsByDay(_ sessions: [Session], calendar: Calendar = .current) -> [[Session]] {
        let sorted = sessions.filter { $0.state == .finished }.sorted { $0.startedAt < $1.startedAt }
        return days.map { day in
            sorted.filter { calendar.isDate($0.startedAt, inSameDayAs: day.date) }
        }
    }

    private static func streak(of sessions: [Session], before weekStart: Date, current: Int, target: Int, calendar: Calendar) -> Int {
        var counts: [Date: Int] = [:]
        for session in sessions where session.startedAt < weekStart {
            if let start = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start {
                counts[start, default: 0] += 1
            }
        }
        var streak = 0
        var cursor = weekStart
        while streak < streakLimit,
              let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor),
              let start = calendar.dateInterval(of: .weekOfYear, for: previous)?.start,
              counts[start, default: 0] >= target {
            streak += 1
            cursor = start
        }
        return current >= target ? streak + 1 : streak
    }
}

/// Brojke jednog treninga za pregled tjedna: trajanje, tvrde serije snage i kardio.
public struct SessionFigures: Equatable, Sendable {
    public var durationSeconds: TimeInterval
    /// Tvrde serije snage (`SetMetrics.isHard`); kardio vježbe se ne broje.
    public var hardSets = 0
    /// Kardio trening cijeli, a u treningu snage zbroj odrađenih kardio vježbi.
    public var cardioSeconds = 0
    /// Udaljenost kardija; nil kad je nema.
    public var cardioMeters: Double?

    public init(durationSeconds: TimeInterval, hardSets: Int = 0, cardioSeconds: Int = 0, cardioMeters: Double? = nil) {
        self.durationSeconds = durationSeconds
        self.hardSets = hardSets
        self.cardioSeconds = cardioSeconds
        self.cardioMeters = cardioMeters
    }

    public init(session: Session, isCardio: (String) -> Bool) {
        durationSeconds = max(0, (session.endedAt ?? session.lastActivityAt).timeIntervalSince(session.startedAt))
        if session.kind == .cardio {
            cardioSeconds = Int(durationSeconds)
            cardioMeters = session.distanceMeters.flatMap { $0 > 0 ? $0 : nil }
        } else {
            let part = SessionCardio.part(of: session, isCardio: isCardio)
            cardioSeconds = part?.seconds ?? 0
            cardioMeters = part?.meters
            for exercise in session.orderedExercises where !exercise.isRemoved && !isCardio(exercise.exerciseKey) {
                hardSets += exercise.orderedSets.filter(\.isCompleted).map(\.values).filter(SetMetrics.isHard).count
            }
        }
    }
}

extension StatisticsEngine {
    /// Tekući tjedan s nizom tjedana, iz vlastitih treninga i treninga iz Zdravlja.
    public func weekProgress(
        now: Date = Date(), goal: Int?, calendar: Calendar = .current, isCardio: (String) -> Bool
    ) throws -> WeekProgress {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let from = calendar.date(byAdding: .weekOfYear, value: -WeekProgress.streakLimit, to: weekStart) ?? weekStart
        let to = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? now
        let sessions = try GymQueries(context: context).finishedSessions(from: from, to: to)
        return WeekProgress.make(sessions: sessions, now: now, goal: goal, calendar: calendar, isCardio: isCardio)
    }

    /// Treninzi tjedna koji počinje s `start` (vlastiti i iz Zdravlja).
    public func sessions(inWeekStarting start: Date, calendar: Calendar = .current) throws -> [Session] {
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        return try GymQueries(context: context).finishedSessions(from: start, to: end)
    }
}
