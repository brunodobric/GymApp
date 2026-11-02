import Foundation

/// Jedinica u kojoj korisnik vidi i unosi težinu.
/// Pravilo iz specifikacije: u bazi se težina UVIJEK sprema u kilogramima,
/// a pretvorba se radi samo za prikaz i unos.
public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kilograms
    case pounds

    public var symbol: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lbs"
        }
    }
}

public enum WeightConversion {
    /// Točna definicija međunarodne funte.
    public static let kilogramsPerPound = 0.45359237

    /// Pretvara vrijednost koju je korisnik unio u kilograme (za spremanje).
    public static func kilograms(from value: Double, in unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: value
        case .pounds: value * kilogramsPerPound
        }
    }

    /// Pretvara spremljene kilograme u jedinicu za prikaz.
    public static func value(fromKilograms kilograms: Double, in unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: kilograms
        case .pounds: kilograms / kilogramsPerPound
        }
    }

    /// Vrijednost za prikaz, zaokružena na korak (npr. 0,25 kg ili 0,5 lbs),
    /// kako 100 lbs spremljeno kao 45,359237 kg ne bi bilo prikazano kao 99,99.
    public static func displayValue(fromKilograms kilograms: Double, in unit: WeightUnit, step: Double = 0.05) -> Double {
        let raw = value(fromKilograms: kilograms, in: unit)
        guard step > 0 else { return raw }
        // Množenje inverzom daje točnije rezultate od dijeljenja s 0,05.
        let stepsPerUnit = (1 / step).rounded()
        guard stepsPerUnit > 0 else { return (raw / step).rounded() * step }
        return (raw * stepsPerUnit).rounded() / stepsPerUnit
    }
}

/// Formatira težinu za prikaz u retku serije, sažetku i grafovima.
public struct WeightFormatter: Sendable {
    public var unit: WeightUnit
    public var locale: Locale

    public init(unit: WeightUnit, locale: Locale = .current) {
        self.unit = unit
        self.locale = locale
    }

    /// Samo broj, npr. "82,5".
    public func number(fromKilograms kilograms: Double) -> String {
        let value = WeightConversion.displayValue(fromKilograms: kilograms, in: unit)
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// Broj s jedinicom, npr. "82,5 kg".
    public func string(fromKilograms kilograms: Double) -> String {
        "\(number(fromKilograms: kilograms)) \(unit.symbol)"
    }
}
