import Foundation

/// Pretvorba teksta iz polja u brojeve i natrag. Prihvaća i zarez i točku kao decimalni znak.
///
/// Prihvaća samo konačne brojeve od nule do `maximum`: tekst kao "inf", "nan", "-20" ili "1e400"
/// (tipkovnica na iPadu, lijepljenje) daje `nil`, da u bazu ne uđe beskonačna ili negativna vrijednost.
public enum NumberInput {
    /// Najveća vrijednost koju polje prihvaća. Dovoljno za težinu, udaljenost i mjere tijela.
    public static let maximum: Double = 100_000

    public static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let value: Double?
        if let localized = try? Double(trimmed, format: .number.locale(locale)) {
            value = localized
        } else {
            value = Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }
        guard let value, isAcceptable(value) else { return nil }
        return value
    }

    /// Broj je konačan i u dopuštenom rasponu (0 do `maximum`). Koristi ga i uvoz sigurnosne kopije.
    public static func isAcceptable(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximum
    }

    public static func format(_ value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale).grouping(.never))
    }
}

/// Trajanje u poljima: "1:30" ili samo sekunde ("90").
///
/// Negativni dijelovi i trajanje dulje od `maximumSeconds` daju `nil`, pa vrlo dug broj
/// ne može preliti `Int` i srušiti aplikaciju.
public enum DurationInput {
    /// Najdulje trajanje koje polje prihvaća: tjedan dana.
    public static let maximumSeconds = 7 * 24 * 3600

    public static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0
        for part in parts {
            // Svaki dio je između 0 i najduljeg trajanja, pa množenje sa 60 ne može preliti `Int`.
            guard let part, part >= 0, part <= maximumSeconds else { return nil }
            total = total * 60 + part
            guard total <= maximumSeconds else { return nil }
        }
        return total
    }

    public static func format(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
