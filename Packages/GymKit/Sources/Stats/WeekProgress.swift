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
            let duration = max(0, (session.endedAt ?? session.lastActivityAt).timeIntervalSince(session.startedAt))
            progress.totalSeconds += duration
            let mix = SessionCardio.mix(of: session, isCardio: isCardio)
            if session.kind == .cardio {
                progress.cardioSeconds += Int(duration)
            } else {
                progress.cardioSeconds += SessionCardio.part(of: session, isCardio: isCardio)?.seconds ?? 0
                for exercise in session.orderedExercises where !exercise.isRemoved && !isCardio(exercise.exerciseKey) {
                    progress.hardSets += exercise.orderedSets.filter(\.isCompleted).map(\.values).filter(SetMetrics.isHard).count
                }
            }
            if let index = progress.days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: session.startedAt) }) {
                if mix.kinds.contains(.strength) { progress.days[index].strength = true }
                if mix.kinds.contains(.cardio) { progress.days[index].cardio = true }
            }
        }
        progress.streakWeeks = streak(of: finished, before: week.start, current: progress.sessions,
                                      target: progress.weeklyTarget, calendar: calendar)
        return progress
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
}
