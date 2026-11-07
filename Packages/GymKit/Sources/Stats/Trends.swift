import Foundation

/// Stanje napretka jedne vježbe u zadnjih nekoliko tjedana.
public enum ExerciseStatus: String, Sendable, CaseIterable {
    case improving
    case stable
    /// Stoji barem `TrendAnalysis.plateauDays` dana.
    case plateau
    case declining
    case insufficientData
}

public struct TrendPoint: Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct ExerciseTrend: Equatable, Sendable {
    public let status: ExerciseStatus
    /// Relativna promjena mjesečno (0,02 = +2 % mjesečno). Pozitivno je uvijek napredak.
    public let monthlyChange: Double?
    /// Uobičajeno kolebanje vrijednosti između treninga (udio), polazno ili naučeno iz podataka.
    public let noise: Double
    /// Broj izvođenja u razdoblju.
    public let sessions: Int
    public let latest: Double?
}

/// Što trend vježbe mjeri.
public enum TrendMeasure: String, Sendable {
    /// Najbolja pouzdana procjena 1RM treninga (vježbe s teretom).
    case oneRepMax
    /// Najviše ponavljanja u seriji (vlastita težina).
    case reps
}

/// Trend napretka iz točaka po treningu: Theil–Senov nagib logaritma vrijednosti (medijan nagiba svih parova
/// točaka), otporan na jedan loš ili iznimno dobar dan. Promjena se uspoređuje s kolebanjem vježbe, pa
/// "napreduje" znači više od šuma, a ne samo jedan bolji dan (Hopkins 2000).
public enum TrendAnalysis {
    public static let minimumSessions = 4
    public static let windowWeeks = 8
    /// Od toliko izvođenja kolebanje se uči iz podataka korisnika.
    public static let learnedNoiseSessions = 6
    public static let noiseRange: ClosedRange<Double> = 0.02...0.08
    /// Najmanja mjesečna promjena koja se računa kao napredak ili pad.
    public static let minimumMonthlyChange = 0.005
    /// Vježba koja stoji ovoliko dana je na platou.
    public static let plateauDays = 28.0
    private static let day: TimeInterval = 24 * 3600

    /// Polazno kolebanje dok nema dovoljno podataka: složene vježbe 3 %, ostale 5 % (procjena iz pouzdanosti
    /// mjerenja 1RM, Grgic i sur. 2020, i grubljih koraka težine kod izolacijskih vježbi).
    public static func defaultNoise(isCompound: Bool?, measure: TrendMeasure = .oneRepMax) -> Double {
        if measure == .reps { return 0.08 }
        return isCompound == true ? 0.03 : 0.05
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Medijan nagiba svih parova točaka s različitim x. Nil za manje od dvije takve točke.
    public static func theilSenSlope(_ points: [(x: Double, y: Double)]) -> Double? {
        var slopes: [Double] = []
        for first in points.indices {
            for second in points.indices where second > first && points[second].x != points[first].x {
                slopes.append((points[second].y - points[first].y) / (points[second].x - points[first].x))
            }
        }
        return median(slopes)
    }

    /// Trend točaka u zadnjih `windowWeeks` tjedana do `now`. `higherIsBetter` je false kad je manje bolje (npr. pomoć).
    public static func trend(
        of points: [TrendPoint], endingAt now: Date, windowWeeks: Int = windowWeeks,
        higherIsBetter: Bool = true, defaultNoise: Double
    ) -> ExerciseTrend {
        let start = now.addingTimeInterval(-Double(windowWeeks) * 7 * day)
        let window = points.filter { $0.date >= start && $0.date <= now && $0.value > 0 }.sorted { $0.date < $1.date }
        let insufficient = ExerciseTrend(
            status: .insufficientData, monthlyChange: nil, noise: defaultNoise, sessions: window.count, latest: window.last?.value
        )
        guard window.count >= minimumSessions, let first = window.first, let last = window.last, last.date > first.date else {
            return insufficient
        }
        let sign = higherIsBetter ? 1.0 : -1.0
        let samples = window.map { (x: $0.date.timeIntervalSince(first.date) / day, y: sign * log($0.value)) }
        guard let slope = theilSenSlope(samples) else { return insufficient }

        var noise = defaultNoise
        if window.count >= learnedNoiseSessions, let intercept = median(samples.map { $0.y - slope * $0.x }),
           let deviation = median(samples.map { abs($0.y - (intercept + slope * $0.x)) }) {
            // Robusna procjena standardne devijacije iz medijana apsolutnih odstupanja.
            noise = min(max(1.4826 * deviation, noiseRange.lowerBound), noiseRange.upperBound)
        }
        let logMonthly = slope * 30
        let threshold = max(minimumMonthlyChange, noise / Double(window.count).squareRoot())
        let status: ExerciseStatus
        if logMonthly > threshold {
            status = .improving
        } else if logMonthly < -threshold {
            status = .declining
        } else {
            status = last.date.timeIntervalSince(first.date) / day >= plateauDays ? .plateau : .stable
        }
        return ExerciseTrend(
            status: status, monthlyChange: exp(logMonthly) - 1, noise: noise, sessions: window.count, latest: last.value
        )
    }

    /// Točke za trend iz napretka vježbe: procjena 1RM kad je ima, inače ponavljanja (vlastita težina).
    public static func points(from progress: [ExercisePoint]) -> (measure: TrendMeasure, points: [TrendPoint])? {
        let strength = progress.compactMap { point in point.estimatedOneRepMaxKg.map { TrendPoint(date: point.date, value: $0) } }
        if !strength.isEmpty { return (.oneRepMax, strength) }
        let hasLoad = progress.contains { $0.bestWeightKg > 0 }
        let reps = progress.filter { $0.bestReps > 0 }.map { TrendPoint(date: $0.date, value: Double($0.bestReps)) }
        if !hasLoad, !reps.isEmpty { return (.reps, reps) }
        return nil
    }
}
