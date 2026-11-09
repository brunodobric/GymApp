import Catalog
import Foundation
import Models

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

/// Zadane pauze iz Postavki, za vježbe bez vlastite pauze. Složene (višezglobne) vježbe traže dulji
/// odmor od izolacijskih: 2–3 min prema 1–1,5 min (Senna i sur. 2016, Schoenfeld i sur. 2016,
/// Grgic i sur. 2018), a izolacijske preko 90 s gotovo ništa ne dobivaju (Singer i sur. 2024).
/// Opterećenje u kg nije dobar pokazatelj (isti teret je nekome 60 %, a nekome 95 % maksimuma),
/// pa pauza ovisi o vrsti vježbe iz kataloga (`Mechanic`).
public struct RestDefaults: Equatable, Sendable {
    /// Složene vježbe (`Mechanic.compound`).
    public var compoundSeconds: Int
    /// Izolacijske i vježbe bez oznake (vlastite vježbe, kardio, istezanje).
    public var otherSeconds: Int

    public init(compoundSeconds: Int, otherSeconds: Int) {
        self.compoundSeconds = compoundSeconds
        self.otherSeconds = otherSeconds
    }

    /// Ista pauza za sve vježbe.
    public init(uniform seconds: Int) {
        self.init(compoundSeconds: seconds, otherSeconds: seconds)
    }

    /// Tvorničke vrijednosti: 2:30 za složene, 1:30 za ostale.
    public static let standard = RestDefaults(compoundSeconds: 150, otherSeconds: 90)

    /// Zadana pauza nakon vježbe ili kruga superseta. Superset s barem jednom složenom vježbom
    /// dobiva pauzu složenih, jer se odmor ravna prema najzahtjevnijoj vježbi u krugu.
    /// Nil znači da se vrsta vježbe ne zna.
    public func seconds(isCompound flags: [Bool?]) -> Int {
        flags.contains(true) ? compoundSeconds : otherSeconds
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

extension UserSettings {
    /// Zadane pauze iz Postavki.
    public var restDefaults: RestDefaults {
        RestDefaults(compoundSeconds: compoundRestSeconds, otherSeconds: defaultRestSeconds)
    }
}

extension ExerciseCatalog {
    /// Je li vježba složena, po ključu `ExerciseRef.key`. Nil za vlastitu vježbu i vježbu bez oznake.
    public func isCompound(exerciseKey key: String) -> Bool? {
        guard let id = ExerciseRef(key: key, name: "")?.catalogId, let exercise = exercise(withID: id) else { return nil }
        return exercise.mechanic.map { $0 == .compound }
    }
}
