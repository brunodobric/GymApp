import Foundation

/// Rest timer koji se sprema kao trenutak završetka, ne kao preostale sekunde.
/// Nakon oporavka ili povratka iz pozadine isti zapis daje ispravno preostalo vrijeme.
public struct RestTimer: Equatable, Sendable {
    public let startedAt: Date
    public let endsAt: Date

    public init(startedAt: Date, endsAt: Date) {
        self.startedAt = startedAt
        self.endsAt = max(endsAt, startedAt)
    }

    public init(startedAt: Date, seconds: Int) {
        self.init(startedAt: startedAt, endsAt: startedAt.addingTimeInterval(Double(max(0, seconds))))
    }

    public var totalSeconds: TimeInterval { endsAt.timeIntervalSince(startedAt) }

    public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }

    public func isExpired(at now: Date) -> Bool { remaining(at: now) == 0 }

    /// Udio proteklog vremena od 0 do 1, za traku koja teče.
    public func progress(at now: Date) -> Double {
        guard totalSeconds > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / totalSeconds))
    }

    /// +10 / −10 sekundi. Timer se nikad ne skraćuje ispod trenutka pritiska (tada istječe odmah).
    public func adjusted(bySeconds delta: Int, at now: Date) -> RestTimer {
        RestTimer(startedAt: startedAt, endsAt: max(now, endsAt.addingTimeInterval(Double(delta))))
    }
}

public enum RestPolicy {

    /// Pauza nakon serije (specifikacija, superset): 0 nakon svake vježbe u supersetu osim zadnje,
    /// a nakon zadnje vrijedi postavljena pauza vježbe ili superseta, inače zadana iz Postavki.
    /// Vježba izvan superseta je grupa veličine 1.
    public static func seconds(positionInGroup: Int, groupSize: Int, configured: Int?, defaultSeconds: Int) -> Int {
        if groupSize > 1, positionInGroup < groupSize - 1 { return 0 }
        return max(0, configured ?? defaultSeconds)
    }
}

public struct SetPosition: Equatable, Sendable {
    public let exercise: Int
    public let set: Int
}

public enum SupersetSequence {

    /// Naizmjenični redoslijed serija: A1, B1, A2, B2, ... Vježba s manje serija jednostavno ispadne iz kruga.
    public static func order(setCounts: [Int]) -> [SetPosition] {
        let rounds = setCounts.max() ?? 0
        var result: [SetPosition] = []
        for round in 0..<max(rounds, 0) {
            for (exercise, count) in setCounts.enumerated() where round < count {
                result.append(SetPosition(exercise: exercise, set: round))
            }
        }
        return result
    }

    /// Prva serija u naizmjeničnom redoslijedu koja još nije završena.
    public static func nextIncomplete(setCounts: [Int], isCompleted: (SetPosition) -> Bool) -> SetPosition? {
        order(setCounts: setCounts).first { !isCompleted($0) }
    }
}

public enum WorkoutFlow {

    /// Nakon završetka zadnje serije vježbe aplikacija se vraća na prvu nekompletiranu vježbu.
    /// nil znači da je sve završeno (prikazuje se "Završi trening / Dodaj vježbu").
    public static func firstIncompleteExercise(isFullyCompleted: [Bool]) -> Int? {
        isFullyCompleted.firstIndex(of: false)
    }

    /// Što ekran treninga radi nakon što je serija označena završenom.
    public enum Advance: Equatable, Sendable {
        /// Otvorena vježba (ili superset) još ima serija: ostaje otvorena.
        case stay
        /// Otvara se vježba na ovom indeksu.
        case open(Int)
        /// Sve je završeno: nudi se "Završi trening / Dodaj vježbu".
        case finished
    }

    /// Odluka nakon označene serije, bilo na ekranu, u Live Activityju ili na satu.
    /// `openGroupDone` kaže jesu li sve serije otvorene vježbe (i njezina superseta) završene.
    public static func advance(openGroupDone: Bool, isFullyCompleted: [Bool]) -> Advance {
        guard openGroupDone else { return .stay }
        return firstIncompleteExercise(isFullyCompleted: isFullyCompleted).map(Advance.open) ?? .finished
    }

    /// Je li od zadnjeg pogleda označena nova serija. Serija označena izvan ekrana (Live Activity, sat)
    /// prepoznaje se po većem broju završenih serija; poništena ili obrisana serija ne pomiče ekran.
    public static func hasNewCompletion(completedCount: Int, lastSeen: Int) -> Bool {
        completedCount > lastSeen
    }
}

public enum RecoveryAssessment {
    /// Trening bez aktivnosti dulje od ovoga nudi se za zatvaranje.
    public static let staleAfter: TimeInterval = 6 * 3600

    public struct Result: Equatable, Sendable {
        public let isStale: Bool
        /// Kraj treninga ako se zatvara: zadnja završena serija, inače početak.
        public let suggestedEnd: Date
    }

    public static func assess(startedAt: Date, lastActivityAt: Date, lastCompletedSetAt: Date?, now: Date) -> Result {
        Result(
            isStale: now.timeIntervalSince(lastActivityAt) > staleAfter,
            suggestedEnd: lastCompletedSetAt ?? startedAt
        )
    }
}
