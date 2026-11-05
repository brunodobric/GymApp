import SwiftUI
import UIKit

/// Naslovi u navigacijskoj traci u SF Pro Rounded, kao naslovi i brojevi u sadržaju (`Font.screenTitle`).
///
/// SwiftUI `.fontDesign` ne djeluje na traku, pa se font postavlja kroz `UINavigationBar.appearance()`.
/// Veliki naslov je bold i raste s Dynamic Typeom (`UIFontMetrics`), kao sistemski. Mali naslov je
/// semibold 17 pt, kao sistemski, koji također ne raste (veliki tekst pokazuje Large Content Viewer).
/// Font za veliki naslov računa se pri pokretanju, pa promjena veličine teksta vrijedi od sljedećeg pokretanja.
@MainActor
enum NavigationBarFont {
    static func apply() {
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: largeTitle]
        appearance.titleTextAttributes = [.font: inlineTitle]
    }

    private static var largeTitle: UIFont {
        // Osnovna veličina za zadanu veličinu teksta; UIFontMetrics je skalira na trenutnu.
        let base = UIFont.preferredFont(
            forTextStyle: .largeTitle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        return UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: rounded(size: base.pointSize, weight: .bold))
    }

    private static var inlineTitle: UIFont {
        rounded(size: 17, weight: .semibold)
    }

    private static func rounded(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }
}
