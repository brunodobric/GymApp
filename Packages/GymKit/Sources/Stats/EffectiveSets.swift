import Foundation
import Models
import Training

/// Tvrde serije: mjera volumena po mišiću za heatmap, graf serija i usporedbu razdoblja.
///
/// Broje se završene radne serije. Serija s upisanim RPE-om ispod `minimumRPE` (RIR 5 i više) je preslaba
/// da bi se brojala; serija bez RPE-a broji se uvijek. Regija kojoj je vježba glavni mišić dobiva cijelu
/// seriju, a regija koja samo pomaže pola (frakcijsko brojanje, Pelland i sur., Sports Medicine).
/// Kilogrami se namjerno ne broje: tonaža nije usporediva između mišića različite veličine.
public enum EffectiveSets {
    /// Udio serije za regiju koja samo pomaže.
    public static let secondaryWeight = 0.5
    /// Najmanji RPE s kojim se serija broji (RPE 6 = RIR 4).
    public static let minimumRPE = SetMetrics.minimumHardRPE

    /// Je li serija dovoljno teška da se broji.
    public static func isHard(_ set: SetValues) -> Bool {
        SetMetrics.isHard(set)
    }

    /// Tvrde serije jedne vježbe: završene, radne, bez preslabih.
    public static func hardSets(of exercise: SessionExercise) -> [SetValues] {
        guard !exercise.isRemoved else { return [] }
        return exercise.orderedSets.filter(\.isCompleted).map(\.values).filter(isHard)
    }

    /// Tvrde serije po regiji za jednu vježbu: glavne i pomoćne odvojeno (pomoćne još nisu prepolovljene).
    /// Regija koja je i glavna i pomoćna broji se samo kao glavna.
    public static func regionCounts(hardSets count: Int, info: ExerciseInfo) -> [String: RegionShare] {
        guard count > 0 else { return [:] }
        var result: [String: RegionShare] = [:]
        let primary = Set(info.primaryRegions)
        for region in primary { result[region] = RegionShare(primary: count, secondary: 0) }
        for region in Set(info.secondaryRegions).subtracting(primary) {
            result[region] = RegionShare(primary: 0, secondary: count)
        }
        return result
    }
}

/// Serije jedne regije: one u kojima je glavni mišić i one u kojima samo pomaže.
public struct RegionShare: Equatable, Sendable {
    public var primary: Int
    public var secondary: Int

    public init(primary: Int, secondary: Int) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Glavna serija 1, pomoćna `EffectiveSets.secondaryWeight`.
    public var weighted: Double { Double(primary) + Double(secondary) * EffectiveSets.secondaryWeight }
}

/// Fiksna skala boje heatmapa. Razina 0 je bez boje, 4 najtamnija. Intenzitet za crtež je razina / 4.
public enum LoadScale {
    public static let maximumLevel = 4

    /// Prosjek tvrdih serija tjedno: ispod 5 malo, 5 do 9 održavanje, 10 do 20 zona za rast, iznad 20 visoko.
    public static func weeklyLevel(_ sets: Double) -> Int {
        switch sets {
        case ..<0.25: 0
        case ..<5: 1
        case ..<10: 2
        case ...20: 3
        default: 4
        }
    }

    /// Tvrde serije u jednom treningu: 1 do 2, 3 do 5, 6 do 9, 10 i više.
    public static func sessionLevel(_ sets: Double) -> Int {
        switch sets {
        case ..<0.25: 0
        case ..<3: 1
        case ..<6: 2
        case ..<10: 3
        default: 4
        }
    }

    public static func intensity(level: Int) -> Double {
        Double(min(max(level, 0), maximumLevel)) / Double(maximumLevel)
    }
}
