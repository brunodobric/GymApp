import Foundation

/// Raspon osi Y za graf vrijednosti (težina, 1RM, volumen, mjere tijela).
///
/// Automatski raspon Swift Chartsa bez nule (`.automatic(includesZero: false)`) za jednake vrijednosti nema
/// raspona, pa os Y ostane bez oznaka i vidi se samo ravna crta. Ovdje raspon uvijek ima širinu: oko
/// vrijednosti se doda razmak, a za pozitivne vrijednosti donja granica ne ide ispod nule.
public enum ChartValueDomain {
    /// Udio raspona koji se doda iznad i ispod podataka.
    static let paddingFraction = 0.1

    public static func domain(for values: [Double]) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return 0...1 }
        let span = high - low
        let padding: Double
        if span > max(abs(high), 1) * 1e-9 {
            padding = span * paddingFraction
        } else {
            // Sve vrijednosti iste: ±10 % vrijednosti, najmanje 1 jedinica.
            padding = max(abs(high) * paddingFraction, 1)
        }
        let lower = low >= 0 ? max(low - padding, 0) : low - padding
        return lower...(high + padding)
    }
}
