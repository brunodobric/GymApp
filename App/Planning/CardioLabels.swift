import Foundation
import Models
import Training
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

    /// Kardio dio treninga snage u sažetku: "15 min · 3,2 km".
    static func part(_ part: CardioPart) -> String {
        var text = duration(Double(part.seconds))
        if let meters = part.meters { text += " · " + distance(meters) }
        return text
    }

    /// Kardio dio u retku povijesti, samo minute: "15 min kardio". Kardio bez trajanja (npr. guranje
    /// saonica s težinom) je samo "Kardio".
    static func historyLine(_ part: CardioPart) -> String {
        let minutes = Int((Double(part.seconds) / 60).rounded())
        guard minutes > 0 else { return String(localized: "Kardio") }
        return String(localized: "\(minutes) min kardio")
    }

    /// Razlika udaljenosti prema prošlom treningu: "+0,4 km", "−120 m" ili "Isto".
    static func distanceChange(_ meters: Double) -> String {
        guard abs(meters) >= 10 else { return String(localized: "Isto") }
        let sign = meters > 0 ? "+" : "−"
        return sign + distance(abs(meters))
    }

    /// Prosječni tempo: "5:30 /km". Nil bez vremena ili za udaljenost ispod 100 m.
    static func pace(_ part: CardioPart) -> String? {
        guard let meters = part.meters, meters >= 100, part.seconds > 0 else { return nil }
        let perKm = Int((Double(part.seconds) / (meters / 1_000)).rounded())
        return String(format: "%d:%02d", perKm / 60, perKm % 60) + " /km"
    }

    /// Prosječna brzina: "10,9 km/h". Nil bez vremena ili za udaljenost ispod 100 m.
    static func speed(_ part: CardioPart) -> String? {
        guard let meters = part.meters, meters >= 100, part.seconds > 0 else { return nil }
        let kmh = (meters / 1_000) / (Double(part.seconds) / 3_600)
        return kmh.formatted(.number.precision(.fractionLength(1))) + " km/h"
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
