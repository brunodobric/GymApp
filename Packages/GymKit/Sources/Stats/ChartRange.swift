import Foundation

/// Raspon koji prikazuje graf napretka vježbe: zadnjih N mjeseci, sve ili vlastiti raspon od–do.
public enum ChartRange: Hashable, Sendable {
    case months(Int)
    case all
    /// Vlastiti raspon; oba datuma ulaze cijelim danom.
    case custom(from: Date, to: Date)

    /// Gotovi rasponi za odabir (bez vlastitog).
    public static let presets: [ChartRange] = [.months(1), .months(2), .months(6), .months(12), .all]

    /// Interval rasponu na dan `now`; nil za "sve". Vlastiti raspon s obrnutim datumima se okrene.
    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case let .months(count):
            let start = calendar.date(byAdding: .month, value: -max(count, 1), to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: max(now, start))
        case let .custom(from, to):
            let first = calendar.startOfDay(for: min(from, to))
            let lastDay = calendar.startOfDay(for: max(from, to))
            // Kraj je zadnji trenutak zadnjeg dana, da ponoć sljedećeg dana ne uđe u raspon.
            let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return DateInterval(start: first, end: nextDay.addingTimeInterval(-0.001))
        }
    }

    /// Točke koje padaju u raspon (granice uključene).
    public func filter(_ points: [ExercisePoint], now: Date, calendar: Calendar = .current) -> [ExercisePoint] {
        guard let interval = interval(now: now, calendar: calendar) else { return points }
        return points.filter { interval.contains($0.date) }
    }
}
