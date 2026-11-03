import Foundation

// Plan kardio treninga (faza 10). Iz njega aplikacija slaže WorkoutKit `CustomWorkout` i zakazuje ga
// u aplikaciju Workout na satu. Model je neovisan o WorkoutKitu, pa se logika može testirati na Macu.

/// Vrste kardija koje aplikacija zakazuje na sat. Sve podržavaju vlastite treninge u aplikaciji Workout.
public enum CardioActivity: String, Codable, CaseIterable, Sendable {
    case running
    case walking
    case cycling
    case hiking
}

public enum CardioLocation: String, Codable, CaseIterable, Sendable {
    case outdoor
    case indoor
}

/// Cilj jednog koraka: bez cilja, vrijeme ili udaljenost.
public enum CardioGoal: Codable, Equatable, Hashable, Sendable {
    case open
    case time(seconds: Double)
    case distance(meters: Double)

    /// Cilj s pozitivnom vrijednošću (ili bez cilja).
    public var isValid: Bool {
        switch self {
        case .open: true
        case .time(let seconds): seconds > 0
        case .distance(let meters): meters > 0
        }
    }
}

/// Blok intervala: rad i opcionalni oporavak, ponovljeni `repeats` puta.
/// Obično trčanje je jedan blok s jednim ponavljanjem i bez oporavka.
public struct CardioInterval: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var work: CardioGoal
    public var recovery: CardioGoal?
    public var repeats: Int

    public init(id: UUID = UUID(), work: CardioGoal, recovery: CardioGoal? = nil, repeats: Int = 1) {
        self.id = id
        self.work = work
        self.recovery = recovery
        self.repeats = repeats
    }
}

public struct CardioPlan: Codable, Equatable, Hashable, Sendable {
    public var activity: CardioActivity
    public var location: CardioLocation
    public var warmup: CardioGoal?
    public var intervals: [CardioInterval]
    public var cooldown: CardioGoal?

    public init(
        activity: CardioActivity = .running, location: CardioLocation = .outdoor, warmup: CardioGoal? = nil,
        intervals: [CardioInterval], cooldown: CardioGoal? = nil
    ) {
        self.activity = activity
        self.location = location
        self.warmup = warmup
        self.intervals = intervals
        self.cooldown = cooldown
    }

    /// Plan se može zakazati: barem jedan blok, svaki s barem jednim ponavljanjem i ispravnim ciljevima.
    public var isValid: Bool {
        guard !intervals.isEmpty else { return false }
        let goals = [warmup, cooldown].compactMap { $0 } + intervals.flatMap { [$0.work] + [$0.recovery].compactMap { $0 } }
        return intervals.allSatisfy { $0.repeats >= 1 } && goals.allSatisfy(\.isValid)
    }

    /// Ukupna udaljenost koraka s ciljem udaljenosti, u metrima (za prikaz).
    public var totalDistanceMeters: Double {
        let blocks = intervals.reduce(0.0) { sum, interval in
            sum + Double(interval.repeats) * (Self.meters(interval.work) + Self.meters(interval.recovery))
        }
        return Self.meters(warmup) + blocks + Self.meters(cooldown)
    }

    /// Ukupno trajanje koraka s ciljem vremena, u sekundama (za prikaz).
    public var totalTimeSeconds: Double {
        let blocks = intervals.reduce(0.0) { sum, interval in
            sum + Double(interval.repeats) * (Self.seconds(interval.work) + Self.seconds(interval.recovery))
        }
        return Self.seconds(warmup) + blocks + Self.seconds(cooldown)
    }

    private static func meters(_ goal: CardioGoal?) -> Double {
        if case .distance(let meters) = goal { return meters }
        return 0
    }

    private static func seconds(_ goal: CardioGoal?) -> Double {
        if case .time(let seconds) = goal { return seconds }
        return 0
    }

    // MARK: Spremanje

    /// Tekst za `WorkoutTemplate.cardioPlanRaw`. Ključevi su sortirani, pa je isti plan uvijek isti tekst.
    public var encoded: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ raw: String?) -> CardioPlan? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CardioPlan.self, from: data)
    }
}

/// Gotovi kardio predlošci koje korisnik bira pri stvaranju kardio treninga.
public enum CardioPreset: String, CaseIterable, Sendable, Identifiable {
    case easyRun
    case run5k
    case minuteIntervals
    case trackIntervals

    public var id: String { rawValue }

    public var plan: CardioPlan {
        switch self {
        case .easyRun:
            CardioPlan(intervals: [CardioInterval(work: .time(seconds: 30 * 60))])
        case .run5k:
            CardioPlan(
                warmup: .time(seconds: 10 * 60),
                intervals: [CardioInterval(work: .distance(meters: 5_000))],
                cooldown: .time(seconds: 5 * 60)
            )
        case .minuteIntervals:
            CardioPlan(
                warmup: .time(seconds: 10 * 60),
                intervals: [CardioInterval(work: .time(seconds: 60), recovery: .time(seconds: 60), repeats: 8)],
                cooldown: .time(seconds: 5 * 60)
            )
        case .trackIntervals:
            CardioPlan(
                warmup: .time(seconds: 10 * 60),
                intervals: [CardioInterval(work: .distance(meters: 400), recovery: .time(seconds: 90), repeats: 6)],
                cooldown: .time(seconds: 10 * 60)
            )
        }
    }
}
