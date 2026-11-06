import Foundation
import Models
import Training

/// Serije jednog treninga po regiji tijela (za prikaz mišića u sažetku i detaljima treninga).
public struct RegionSets: Equatable, Sendable {
    public let region: String
    /// Tvrde serije vježbi kojima je regija glavni mišić.
    public var primarySets: Int
    /// Tvrde serije vježbi kojima regija samo pomaže.
    public var secondarySets: Int
    public var volumeKg: Double

    public init(region: String, primarySets: Int = 0, secondarySets: Int = 0, volumeKg: Double = 0) {
        self.region = region
        self.primarySets = primarySets
        self.secondarySets = secondarySets
        self.volumeKg = volumeKg
    }

    /// Serije za boju i popis: glavna serija broji se kao 1, pomoćna kao `EffectiveSets.secondaryWeight`.
    public var weightedSets: Double {
        RegionShare(primary: primarySets, secondary: secondarySets).weighted
    }

    /// Razina na fiksnoj skali jednog treninga (`LoadScale.sessionLevel`).
    public var level: Int { LoadScale.sessionLevel(weightedSets) }
}

/// Mišićne regije koje je jedan trening opteretio.
public enum SessionRegions {
    /// Udio pomoćne serije u odnosu na seriju u kojoj je regija glavni mišić.
    public static let secondaryWeight = EffectiveSets.secondaryWeight

    /// Serije po regiji, od najopterećenije. Broje se tvrde serije (`EffectiveSets`); warm-up, preslabe
    /// serije i uklonjene vježbe se ne računaju. Regija bez ijedne serije nije u popisu.
    public static func sets(in session: Session, info: ExerciseInfoProvider) -> [RegionSets] {
        var result: [String: RegionSets] = [:]
        for exercise in session.orderedExercises where !exercise.isRemoved {
            guard let details = info(exercise.exerciseKey) else { continue }
            let done = EffectiveSets.hardSets(of: exercise)
            guard !done.isEmpty else { continue }
            let volume = done.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
            for (region, share) in EffectiveSets.regionCounts(hardSets: done.count, info: details) {
                var load = result[region] ?? RegionSets(region: region)
                load.primarySets += share.primary
                load.secondarySets += share.secondary
                load.volumeKg += share.primary > 0 ? volume : volume * secondaryWeight
                result[region] = load
            }
        }
        return result.values.sorted {
            $0.weightedSets != $1.weightedSets ? $0.weightedSets > $1.weightedSets : $0.region < $1.region
        }
    }

    /// Popis ispod mape dijeli regije na glavne (barem jedna serija u kojoj su glavni mišić) i one koje samo
    /// pomažu. Redoslijed iz `sets(in:info:)` ostaje unutar obje skupine.
    public static func split(_ sets: [RegionSets]) -> (primary: [RegionSets], assisting: [RegionSets]) {
        (sets.filter { $0.primarySets > 0 }, sets.filter { $0.primarySets == 0 })
    }

    /// Heatmap treninga na fiksnoj skali: boja ovisi o broju serije regije, ne o najopterećenijoj regiji,
    /// pa lagan trening ostaje svijetao.
    public static func heatmap(_ sets: [RegionSets]) -> [String: RegionLoad] {
        var result: [String: RegionLoad] = [:]
        for load in sets where load.weightedSets > 0 {
            result[load.region] = RegionLoad(
                sessions: 1, volumeKg: load.volumeKg, sets: load.weightedSets,
                weeklySets: load.weightedSets, intensity: LoadScale.intensity(level: load.level)
            )
        }
        return result
    }

    /// Heatmap regija koje je trening opteretio (vidi `sets(in:info:)` i `heatmap(_:)`).
    public static func worked(in session: Session, info: ExerciseInfoProvider) -> [String: RegionLoad] {
        heatmap(sets(in: session, info: info))
    }
}
