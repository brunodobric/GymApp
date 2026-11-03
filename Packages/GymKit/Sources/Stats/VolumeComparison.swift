import Catalog
import Foundation

/// Volumen jednog mišića u dva uzastopna razdoblja.
public struct MuscleComparison: Equatable, Sendable {
    public let muscle: Muscle
    public let currentKg: Double
    public let previousKg: Double
}

/// Usporedba zadnjeg razdoblja (tjedna ili mjeseca, koji je možda još u tijeku) s prethodnim.
/// Služi za graf usporedbe u statistici (faza 11).
public struct VolumeComparison: Equatable, Sendable {
    public let currentStart: Date
    public let previousStart: Date
    public let currentKg: Double
    public let previousKg: Double
    /// Mišići s volumenom u barem jednom od dva razdoblja, od najvećeg volumena prema manjem.
    public let muscles: [MuscleComparison]

    /// Relativna promjena ukupnog volumena (0,1 = +10 %). Bez volumena u prethodnom razdoblju nema smisla.
    public var change: Double? {
        previousKg > 0 ? (currentKg - previousKg) / previousKg : nil
    }

    /// `buckets` su od najstarijeg prema najnovijem, kao iz `StatisticsEngine.volumeBuckets`.
    /// Uspoređuju se zadnja dva. Bez barem dva razdoblja usporedbe nema.
    public init?(buckets: [VolumeBucket]) {
        guard buckets.count >= 2 else { return nil }
        let current = buckets[buckets.count - 1]
        let previous = buckets[buckets.count - 2]
        currentStart = current.start
        previousStart = previous.start
        currentKg = current.totalVolumeKg
        previousKg = previous.totalVolumeKg
        let all = Set(current.loads.keys).union(previous.loads.keys)
        muscles = all
            .map { muscle in
                MuscleComparison(
                    muscle: muscle,
                    currentKg: current.loads[muscle]?.volumeKg ?? 0,
                    previousKg: previous.loads[muscle]?.volumeKg ?? 0
                )
            }
            .filter { $0.currentKg > 0 || $0.previousKg > 0 }
            .sorted { lhs, rhs in
                let left = max(lhs.currentKg, lhs.previousKg)
                let right = max(rhs.currentKg, rhs.previousKg)
                // Jednaki volumen: stalan redoslijed po nazivu, da se graf ne miješa između učitavanja.
                return left == right ? lhs.muscle.rawValue < rhs.muscle.rawValue : left > right
            }
    }
}
