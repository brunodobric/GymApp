import Foundation

/// Koje ploče staviti na šipku. Radi u jednoj jedinici (kg ili lbs): sve vrijednosti
/// (cilj, šipka, ploče) moraju biti u istoj jedinici, a rezultat je u njoj.
public enum PlateCalculator {

    public struct Result: Equatable, Sendable {
        /// Ploče za jednu stranu šipke, od najteže prema najlakšoj.
        public let perSide: [Double]
        /// Ukupna težina koja se može postići (šipka + obje strane).
        public let achievedTotal: Double
        /// Koliko nedostaje do cilja (0 kad je točno). Negativna vrijednost nije moguća.
        public let shortfall: Double
        public let isExact: Bool
        /// Cilj je manji od same šipke.
        public let isBelowBar: Bool
    }

    /// Najbliža težina koja ne prelazi cilj, uz najmanje ploča. Svaka ploča se može koristiti koliko god puta.
    public static func calculate(target: Double, barbell: Double, plates: [Double]) -> Result {
        guard target >= barbell - 1e-9 else {
            return Result(perSide: [], achievedTotal: barbell, shortfall: 0, isExact: false, isBelowBar: true)
        }
        let unit = 100.0 // stotinke jedinice, da decimale poput 1,25 budu cijeli brojevi
        let sizes = Set(plates.filter { $0 > 0 }.map { Int(($0 * unit).rounded()) }).sorted(by: >)
        let perSideTarget = Int((((target - barbell) / 2) * unit).rounded(.down) + 1e-6)
        guard !sizes.isEmpty, perSideTarget > 0 else {
            let exact = perSideTarget == 0
            return Result(perSide: [], achievedTotal: barbell, shortfall: exact ? 0 : target - barbell, isExact: exact, isBelowBar: false)
        }

        // Najmanji broj ploča za svaku težinu do cilja (neograničeni "coin change").
        var fewest = [Int](repeating: Int.max, count: perSideTarget + 1)
        var lastPlate = [Int](repeating: 0, count: perSideTarget + 1)
        fewest[0] = 0
        if perSideTarget >= 1 {
            for weight in 1...perSideTarget {
                for size in sizes where size <= weight && fewest[weight - size] != Int.max {
                    let count = fewest[weight - size] + 1
                    if count < fewest[weight] {
                        fewest[weight] = count
                        lastPlate[weight] = size
                    }
                }
            }
        }
        var reached = perSideTarget
        while reached > 0, fewest[reached] == Int.max { reached -= 1 }

        var plateSizes: [Int] = []
        var remaining = reached
        while remaining > 0 {
            plateSizes.append(lastPlate[remaining])
            remaining -= lastPlate[remaining]
        }
        let perSide = plateSizes.sorted(by: >).map { Double($0) / unit }
        let achieved = barbell + perSide.reduce(0, +) * 2
        let shortfall = max(0, target - achieved)
        return Result(
            perSide: perSide, achievedTotal: achieved,
            shortfall: shortfall < 1e-6 ? 0 : shortfall, isExact: shortfall < 1e-6, isBelowBar: false
        )
    }

    public struct PlateCount: Equatable, Sendable {
        public let plate: Double
        public let count: Int
    }

    /// Ploče jedne strane grupirane po veličini, od najteže: [20, 20, 5] daje 2×20 i 1×5.
    public static func grouped(_ perSide: [Double]) -> [PlateCount] {
        var result: [PlateCount] = []
        for plate in perSide {
            if let last = result.last, last.plate == plate {
                result[result.count - 1] = PlateCount(plate: plate, count: last.count + 1)
            } else {
                result.append(PlateCount(plate: plate, count: 1))
            }
        }
        return result
    }

    /// Uobičajene ploče i šipka za funte (postavke ploča čuvaju se u kilogramima).
    public static let defaultPoundPlates: [Double] = [2.5, 5, 10, 25, 35, 45]
    public static let defaultPoundBarbell: Double = 45
}
