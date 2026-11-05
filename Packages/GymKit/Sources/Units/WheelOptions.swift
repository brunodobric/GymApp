import Foundation

/// Vrijednosti koje nudi kotačić za unos težine i ponavljanja u retku serije.
/// Sve vrijednosti su u jedinici za prikaz (kg ili lbs), a pretvorba u kilograme ide pri spremanju.
public enum WheelOptions {
    /// Najmanja i najveća ponuđena ponavljanja.
    public static let repsRange = 1...50

    /// Korak težine: 2,5 kg ili 5 lbs (najmanji uobičajeni skok s parom ploča).
    public static func weightStep(for unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: 2.5
        case .pounds: 5
        }
    }

    /// Najveća ponuđena težina. Veća se može upisati tipkovnicom.
    public static func maximumWeight(for unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: 500
        case .pounds: 1100
        }
    }

    /// Početna težina kad serija i prošli trening nemaju vrijednost: prazna olimpijska šipka,
    /// a za dodatnu težinu ili pomoć nula.
    public static func defaultWeight(for unit: WeightUnit, isExtraLoad: Bool) -> Double {
        if isExtraLoad { return 0 }
        return unit == .kilograms ? 20 : 45
    }

    /// Početna ponavljanja kad serija i prošli trening nemaju vrijednost.
    public static let defaultReps = 10

    /// Težine od 0 do najveće u koracima jedinice. Vrijednost koja nije na koraku (npr. 83 kg upisano
    /// tipkovnicom) dodaje se na svoje mjesto, da je kotačić može prikazati i da se ne promijeni sama.
    public static func weights(for unit: WeightUnit, including current: Double? = nil) -> [Double] {
        let step = weightStep(for: unit)
        let count = Int((maximumWeight(for: unit) / step).rounded())
        var values = (0...count).map { Double($0) * step }
        if let current, current >= 0, !values.contains(where: { abs($0 - current) < tolerance }) {
            let index = values.firstIndex(where: { $0 > current }) ?? values.endIndex
            values.insert(current, at: index)
        }
        return values
    }

    /// Ponavljanja od 1 do 50, uz trenutnu vrijednost ako je izvan raspona (npr. 60 upisano tipkovnicom).
    public static func reps(including current: Int? = nil) -> [Int] {
        var values = Array(repsRange)
        if let current, current >= 0, !repsRange.contains(current) {
            let index = values.firstIndex(where: { $0 > current }) ?? values.endIndex
            values.insert(current, at: index)
        }
        return values
    }

    /// Vrijednost s popisa najbliža zadanoj, na koju se kotačić postavi kad se otvori.
    public static func nearest(to value: Double, in options: [Double]) -> Double? {
        options.min { abs($0 - value) < abs($1 - value) }
    }

    /// Razlika ispod koje se dvije težine za prikaz smatraju jednakima (prikaz se zaokružuje na 0,05).
    static let tolerance = 0.001
}
