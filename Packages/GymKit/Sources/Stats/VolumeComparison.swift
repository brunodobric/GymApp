import Foundation

/// Tvrde serije jedne regije tijela u dva uzastopna razdoblja.
public struct MuscleComparison: Equatable, Sendable {
    public let region: String
    public let currentSets: Double
    public let previousSets: Double
}

/// Usporedba zadnjeg razdoblja (tjedna ili mjeseca, koji je možda još u tijeku) s prethodnim, u tvrdim serijama.
/// Služi za graf usporedbe u statistici.
public struct VolumeComparison: Equatable, Sendable {
    public let currentStart: Date
    public let previousStart: Date
    /// Ukupno tvrdih serija; svaka serija broji se jednom.
    public let currentSets: Int
    public let previousSets: Int
    /// Regije sa serijama u barem jednom od dva razdoblja, od najviše serija prema manje.
    public let muscles: [MuscleComparison]

    /// Relativna promjena ukupnog broja serija (0,1 = +10 %). Bez serija u prethodnom razdoblju nema smisla.
    public var change: Double? {
        previousSets > 0 ? Double(currentSets - previousSets) / Double(previousSets) : nil
    }

    /// `buckets` su od najstarijeg prema najnovijem, kao iz `StatisticsEngine.volumeBuckets`.
    /// Uspoređuju se zadnja dva. Bez barem dva razdoblja usporedbe nema.
    public init?(buckets: [VolumeBucket]) {
        guard buckets.count >= 2 else { return nil }
        let current = buckets[buckets.count - 1]
        let previous = buckets[buckets.count - 2]
        currentStart = current.start
        previousStart = previous.start
        currentSets = current.totalSets
        previousSets = previous.totalSets
        let all = Set(current.loads.keys).union(previous.loads.keys)
        muscles = all
            .map { region in
                MuscleComparison(
                    region: region,
                    currentSets: current.loads[region]?.sets ?? 0,
                    previousSets: previous.loads[region]?.sets ?? 0
                )
            }
            .filter { $0.currentSets > 0 || $0.previousSets > 0 }
            .sorted { lhs, rhs in
                let left = max(lhs.currentSets, lhs.previousSets)
                let right = max(rhs.currentSets, rhs.previousSets)
                // Jednako serija: stalan redoslijed po nazivu, da se graf ne miješa između učitavanja.
                return left == right ? lhs.region < rhs.region : left > right
            }
    }
}
