import Foundation
import Models
import Training
import Units

// Tekstovi za kardio na treningu. Udaljenost je uvijek metrička (km i m), kao u unosu kardija.

enum CardioText {
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
}
