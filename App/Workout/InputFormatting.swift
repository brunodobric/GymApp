import Foundation

/// Pretvorba teksta iz polja u brojeve i natrag. Prihvaća i zarez i točku kao decimalni znak.
enum NumberInput {
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let value = try? Double(trimmed, format: .number.locale(locale)) { return value }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ value: Double?, locale: Locale = .current) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale).grouping(.never))
    }
}

/// Trajanje u poljima: "1:30" ili samo sekunde ("90").
enum DurationInput {
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":").map { Int($0) }
        if parts.contains(where: { $0 == nil }) { return nil }
        let numbers = parts.compactMap { $0 }
        switch numbers.count {
        case 1: return numbers[0]
        case 2: return numbers[0] * 60 + numbers[1]
        case 3: return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default: return nil
        }
    }

    static func format(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
