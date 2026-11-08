import Foundation

extension WidgetSnapshot {
    /// Tekući tjedan kao na kartici Ovaj tjedan (`WeekProgress`), bez ovisnosti o bazi.
    public struct Week: Codable, Equatable, Sendable {
        public struct Day: Codable, Equatable, Sendable {
            public var date: Date
            public var strength: Bool
            public var cardio: Bool

            public init(date: Date, strength: Bool = false, cardio: Bool = false) {
                self.date = date
                self.strength = strength
                self.cardio = cardio
            }

            public var isTrained: Bool { strength || cardio }

            public var mix: Mix? {
                switch (strength, cardio) {
                case (true, true): .mixed
                case (true, false): .strength
                case (false, true): .cardio
                case (false, false): nil
                }
            }
        }

        public var start: Date
        public var days: [Day]
        public var sessions: Int
        public var goal: Int?
        public var streakWeeks: Int
        public var hardSets: Int
        public var cardioSeconds: Int
        public var totalSeconds: Int

        public init(
            start: Date, days: [Day], sessions: Int, goal: Int?, streakWeeks: Int,
            hardSets: Int = 0, cardioSeconds: Int = 0, totalSeconds: Int = 0
        ) {
            self.start = start
            self.days = days
            self.sessions = sessions
            self.goal = goal.flatMap { $0 > 0 ? $0 : nil }
            self.streakWeeks = streakWeeks
            self.hardSets = hardSets
            self.cardioSeconds = cardioSeconds
            self.totalSeconds = totalSeconds
        }

        /// Tjedan s praznim danima od `start`.
        public init(
            start: Date, sessions: Int, goal: Int?, streakWeeks: Int, hardSets: Int = 0, cardioSeconds: Int = 0,
            totalSeconds: Int = 0, calendar: Calendar = .current
        ) {
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { Day(date: $0) }
            self.init(start: start, days: days, sessions: sessions, goal: goal, streakWeeks: streakWeeks,
                      hardSets: hardSets, cardioSeconds: cardioSeconds, totalSeconds: totalSeconds)
        }

        /// Udio cilja (0 do 1); nil bez cilja.
        public var goalFraction: Double? {
            guard let goal, goal > 0 else { return nil }
            return min(Double(sessions) / Double(goal), 1)
        }

        /// Koliko treninga treba da se tjedan broji u niz (bez cilja: jedan), kao `WeekProgress`.
        var weeklyTarget: Int { max(goal ?? 1, 1) }

        /// Tjedan kakav je u trenutku `now`. Snimka je složena ranije, pa widget koji ostane do idućeg tjedna
        /// mora pokazati prazan tjedan: niz se nastavlja samo ako je upravo završeni tjedan ispunio cilj,
        /// a prazan tjedan između prekida ga.
        public func current(at now: Date, calendar: Calendar = .current) -> Week {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now),
                  interval.start > start, !calendar.isDate(interval.start, inSameDayAs: start) else { return self }
            let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start)
            let isNextWeek = previous.map { calendar.isDate($0, inSameDayAs: start) } ?? false
            let continues = isNextWeek && sessions >= weeklyTarget
            return Week(start: interval.start, sessions: 0, goal: goal, streakWeeks: continues ? streakWeeks : 0, calendar: calendar)
        }
    }
}
