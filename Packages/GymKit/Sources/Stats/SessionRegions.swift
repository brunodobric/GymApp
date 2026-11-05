import Foundation
import Models
import Training

/// Serije jednog treninga po regiji tijela (za prikaz mišića u sažetku i detaljima treninga).
public struct RegionSets: Equatable, Sendable {
    public let region: String
    /// Završene radne serije vježbi kojima je regija glavni mišić.
    public var primarySets: Int
    /// Završene radne serije vježbi kojima regija samo pomaže.
    public var secondarySets: Int
    public var volumeKg: Double

    public init(region: String, primarySets: Int = 0, secondarySets: Int = 0, volumeKg: Double = 0) {
        self.region = region
        self.primarySets = primarySets
        self.secondarySets = secondarySets
        self.volumeKg = volumeKg
    }

    /// Serije za boju: glavna serija broji se kao 1, pomoćna kao `SessionRegions.secondaryWeight`.
    public var weightedSets: Double {
        Double(primarySets) + Double(secondarySets) * SessionRegions.secondaryWeight
    }
}

/// Mišićne regije koje je jedan trening opteretio.
public enum SessionRegions {
    /// Udio pomoćne serije u odnosu na seriju u kojoj je regija glavni mišić.
    public static let secondaryWeight = 0.5

    /// Serije po regiji, od najopterećenije. Broje se samo završene radne serije; warm-up i
    /// uklonjene vježbe se ne računaju. Regija bez ijedne serije nije u popisu.
    public static func sets(in session: Session, info: ExerciseInfoProvider) -> [RegionSets] {
        var result: [String: RegionSets] = [:]
        for exercise in session.orderedExercises where !exercise.isRemoved {
            guard let details = info(exercise.exerciseKey) else { continue }
            let done = exercise.orderedSets.filter(\.isCompleted).map(\.values).filter { $0.kind == .working }
            guard !done.isEmpty else { continue }
            let volume = done.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
            let primary = Set(details.primaryRegions)
            for region in primary {
                var load = result[region] ?? RegionSets(region: region)
                load.primarySets += done.count
                load.volumeKg += volume
                result[region] = load
            }
            for region in Set(details.secondaryRegions).subtracting(primary) {
                var load = result[region] ?? RegionSets(region: region)
                load.secondarySets += done.count
                load.volumeKg += volume / 2
                result[region] = load
            }
        }
        return result.values.sorted {
            $0.weightedSets != $1.weightedSets ? $0.weightedSets > $1.weightedSets : $0.region < $1.region
        }
    }

    /// Heatmap treninga: intenzitet regije je broj njenih serija (pomoćne upola) prema najopterećenijoj regiji.
    public static func heatmap(_ sets: [RegionSets]) -> [String: RegionLoad] {
        let maximum = sets.map(\.weightedSets).max() ?? 0
        guard maximum > 0 else { return [:] }
        var result: [String: RegionLoad] = [:]
        for load in sets {
            result[load.region] = RegionLoad(sessions: 1, volumeKg: load.volumeKg, intensity: load.weightedSets / maximum)
        }
        return result
    }

    /// Heatmap regija koje je trening opteretio (vidi `sets(in:info:)` i `heatmap(_:)`).
    public static func worked(in session: Session, info: ExerciseInfoProvider) -> [String: RegionLoad] {
        heatmap(sets(in: session, info: info))
    }
}
