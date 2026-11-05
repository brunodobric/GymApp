import Foundation
import Models
import Units

// Tekstovi za prikaz kardio plana. Udaljenost je uvijek metrička (km i m), kao u unosu kardija na treningu.

extension CardioActivity {
    var title: String {
        switch self {
        case .running: String(localized: "Trčanje")
        case .walking: String(localized: "Hodanje")
        case .cycling: String(localized: "Bicikl")
        case .hiking: String(localized: "Planinarenje")
        }
    }

    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .hiking: "figure.hiking"
        }
    }
}

extension CardioLocation {
    var title: String {
        switch self {
        case .outdoor: String(localized: "Vani")
        case .indoor: String(localized: "Unutra")
        }
    }
}

extension CardioPreset {
    var title: String {
        switch self {
        case .easyRun: String(localized: "Lagano trčanje 30 min")
        case .run5k: String(localized: "Trčanje 5 km")
        case .minuteIntervals: String(localized: "Intervali 8 × 1 min")
        case .trackIntervals: String(localized: "Intervali 6 × 400 m")
        }
    }
}

enum CardioText {
    static func goal(_ goal: CardioGoal) -> String {
        switch goal {
        case .open: String(localized: "bez cilja")
        case .time(let seconds): duration(seconds)
        case .distance(let meters): distance(meters)
        }
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        if minutes == 0 { return "\(rest) s" }
        if rest == 0 { return "\(minutes) min" }
        return "\(minutes) min \(rest) s"
    }

    static func distance(_ meters: Double) -> String {
        if meters >= 1_000 { return NumberInput.format(meters / 1_000) + " km" }
        return "\(Int(meters.rounded())) m"
    }

    /// Npr. "8 × 1 min, oporavak 1 min" ili "5 km".
    static func interval(_ interval: CardioInterval) -> String {
        var text = goal(interval.work)
        if interval.repeats > 1 { text = "\(interval.repeats) × \(text)" }
        if let recovery = interval.recovery {
            text += ", " + String(localized: "oporavak \(goal(recovery))")
        }
        return text
    }

    /// Kratki opis za popise: "Trčanje · 10 min + 5 km + 5 min".
    static func summary(_ plan: CardioPlan) -> String {
        var parts: [String] = []
        if let warmup = plan.warmup { parts.append(goal(warmup)) }
        parts += plan.intervals.map(interval)
        if let cooldown = plan.cooldown { parts.append(goal(cooldown)) }
        return plan.activity.title + " · " + parts.joined(separator: " + ")
    }
}
