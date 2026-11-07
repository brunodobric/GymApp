import Foundation
import Models
import SwiftData
import Training

/// DOTS bodovi: zbroj čučnja, potiska s klupe i mrtvog dizanja prilagođen tjelesnoj masi, da se snaga može
/// usporediti između ljudi različite težine. Formula i koeficijenti su iz powerliftinga (Tim Konertz, 2019;
/// koristi ih OpenPowerlifting). Vrijedi samo za ta tri dizanja sa šipkom, a ovdje se računa iz procjene 1RM,
/// ne iz natjecateljskog maksimuma.
public enum Dots {
    /// Dizanja koja ulaze u zbroj (id iz kataloga): čučanj, potisak s klupe, mrtvo dizanje.
    public static let lifts = ["barbell-squat", "barbell-bench-press", "barbell-deadlift"]

    /// Koeficijenti nazivnika od slobodnog člana do člana uz m⁴.
    static func coefficients(for sex: Sex) -> [Double] {
        switch sex {
        case .male: [-307.75076, 24.0900756, -0.1918759221, 0.0007391293, -0.000001093]
        case .female: [-57.96288, 13.6175032, -0.1126655495, 0.0005158568, -0.0000010706]
        }
    }

    /// Raspon tjelesne mase za koji formula vrijedi; masa izvan njega uzima se kao granica.
    public static func bodyWeightRange(for sex: Sex) -> ClosedRange<Double> {
        switch sex {
        case .male: 40...210
        case .female: 40...150
        }
    }

    /// DOTS = zbroj × 500 / (a + b·m + c·m² + d·m³ + e·m⁴). Nil bez zbroja ili tjelesne mase.
    public static func points(totalKg: Double, bodyWeightKg: Double, sex: Sex) -> Double? {
        guard totalKg > 0, bodyWeightKg > 0 else { return nil }
        let range = bodyWeightRange(for: sex)
        let mass = min(max(bodyWeightKg, range.lowerBound), range.upperBound)
        var power = 1.0
        var denominator = 0.0
        for coefficient in coefficients(for: sex) {
            denominator += coefficient * power
            power *= mass
        }
        guard denominator > 0 else { return nil }
        return totalKg * 500 / denominator
    }
}

/// DOTS iz najbolje procjene 1RM triju dizanja u razdoblju.
public struct DotsScore: Equatable, Sendable {
    /// Najbolja procjena 1RM po dizanju (id iz kataloga), samo za dizanja koja su rađena u razdoblju.
    public let liftsKg: [String: Double]
    public let bodyWeightKg: Double
    public let sex: Sex

    public init(liftsKg: [String: Double], bodyWeightKg: Double, sex: Sex) {
        self.liftsKg = liftsKg
        self.bodyWeightKg = bodyWeightKg
        self.sex = sex
    }

    /// Dizanja koja nedostaju za zbroj.
    public var missingLifts: [String] { Dots.lifts.filter { liftsKg[$0] == nil } }

    /// Zbroj, samo kad su sva tri dizanja rađena.
    public var totalKg: Double? {
        missingLifts.isEmpty ? Dots.lifts.compactMap { liftsKg[$0] }.reduce(0, +) : nil
    }

    public var points: Double? {
        totalKg.flatMap { Dots.points(totalKg: $0, bodyWeightKg: bodyWeightKg, sex: sex) }
    }
}

extension StatisticsEngine {
    /// DOTS iz najbolje pouzdane procjene 1RM čučnja, potiska i mrtvog dizanja u zadnjih `weeks` tjedana.
    /// Nil kad nijedno od tri dizanja nije rađeno u razdoblju.
    public func dotsScore(
        bodyWeightKg: Double, sex: Sex, weeks: Int = 12, endingAt now: Date = Date(),
        formula: SetMetrics.OneRepMaxFormula = .epley
    ) throws -> DotsScore? {
        let start = now.addingTimeInterval(-Double(weeks) * 7 * 24 * 3600)
        var lifts: [String: Double] = [:]
        for id in Dots.lifts {
            let points = try progress(of: ExerciseRef(catalogId: id, name: id), formula: formula)
            let best = points.filter { $0.date >= start && $0.date <= now }.compactMap(\.estimatedOneRepMaxKg).max()
            if let best { lifts[id] = best }
        }
        guard !lifts.isEmpty else { return nil }
        return DotsScore(liftsKg: lifts, bodyWeightKg: bodyWeightKg, sex: sex)
    }
}
