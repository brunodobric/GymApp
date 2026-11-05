import Stats
import SwiftUI

/// Boje mišićnih skupina. Jedino mjesto u aplikaciji s više boja; sve ostalo koristi akcent iz Postavki.
/// Sve su sistemske, pa se prilagođavaju tamnom načinu i postavci Povećaj kontrast.
extension BodyRegion.ColorGroup {
    var color: Color {
        switch self {
        case .chest: .red
        case .shoulders: .orange
        case .biceps: .pink
        case .triceps: .indigo
        case .forearms: .purple
        case .core: .green
        case .back: .teal
        case .legs: .cyan
        case .glutes: .yellow
        }
    }
}

extension BodyRegion {
    /// Boja regije za graf mišića; nepoznata regija je siva.
    static func color(_ region: String) -> Color {
        colorGroup(for: region)?.color ?? .secondary
    }
}
