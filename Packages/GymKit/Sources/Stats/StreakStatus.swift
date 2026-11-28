import Foundation

/// Streak za karticu na Početnoj: uzastopni tjedni s ispunjenim tjednim ciljem (`WeekProgress.streakWeeks`)
/// i što tekući tjedan znači za niz. Kartica tako daje blagi pritisak: koliko treninga još treba do kraja
/// tjedna i gubi li se niz ako ih korisnik ne odradi.
public struct StreakStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Cilj tekućeg tjedna je ispunjen: tjedan je već u nizu.
        case secured
        /// Niz postoji, a tjedan s premalo treninga bi ga prekinuo.
        case atRisk
        /// Niz postoji, a tjedan bez ijednog treninga bio bi pauza (`WeekProgress.streakLength`): niz ostaje,
        /// ali ne raste. Kartica tada samo poziva na sljedeći tjedan niza, bez prijetnje gubitkom.
        case canGrow
        /// Niza još nema: ispunjen cilj ovog tjedna ga započinje.
        case notStarted
    }

    /// Tjedni zaredom, s tekućim tjednom ako je cilj već ispunjen.
    public let weeks: Int
    public let state: State
    /// Odrađeni treninzi u tekućem tjednu.
    public let sessions: Int
    /// Treninzi tjedno koji tjedan stavljaju u niz (cilj iz onboardinga, bez cilja 1).
    public let target: Int
    /// Dani do kraja tjedna, s današnjim (1 je zadnji dan tjedna).
    public let daysLeft: Int

    /// Treninzi koji još nedostaju do cilja ovog tjedna.
    public var remaining: Int { max(target - sessions, 0) }

    /// Zadnji dan tjedna, a cilj još nije ispunjen.
    public var isLastChance: Bool { state == .atRisk && daysLeft <= 1 }

    public init(weeks: Int, state: State, sessions: Int, target: Int, daysLeft: Int) {
        self.weeks = weeks
        self.state = state
        self.sessions = sessions
        self.target = target
        self.daysLeft = daysLeft
    }

    /// Stanje iz tekućeg tjedna (`WeekProgress.make`) u trenutku `now`.
    public init(progress: WeekProgress, now: Date, calendar: Calendar = .current) {
        let target = progress.weeklyTarget
        let state: State
        if progress.sessions >= target {
            state = .secured
        } else if progress.previousStreakWeeks == 0 {
            state = .notStarted
        } else if progress.streakIfWeekEndsNow < progress.previousStreakWeeks {
            state = .atRisk
        } else {
            state = .canGrow
        }
        let end = calendar.date(byAdding: .day, value: progress.days.count, to: progress.start) ?? progress.start
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 1
        self.init(
            weeks: progress.streakWeeks, state: state, sessions: progress.sessions, target: target,
            daysLeft: min(max(days, 1), 7)
        )
    }
}
