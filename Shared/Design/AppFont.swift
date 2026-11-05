import SwiftUI

/// Uloge teksta (docs/DIZAJN.md, odjeljak Tipografija), zajedničke za aplikaciju, widgete i sat.
///
/// Naslovi i brojevi su u SF Pro Rounded, a opisi, gumbi i retci formi u običnom SF Pro
/// (sistemski tekstualni stilovi, npr. `.subheadline`). Svaki stil je tekstualni stil,
/// pa raste s Dynamic Typeom. Brojevi imaju `monospacedDigit()` da se redak ne pomiče.
extension Font {
    // MARK: - Naslovi

    /// Veliki naslov u sadržaju ekrana (naziv treninga na detalju). Isti kao veliki naslov u traci.
    static var screenTitle: Font { Font.system(.largeTitle, design: .rounded, weight: .bold) }
    /// Naslov kartice ili istaknutog retka: naziv treninga na kartici, pitanje u onboardingu.
    static var cardTitle: Font { Font.system(.title3, design: .rounded, weight: .bold) }
    /// Naziv vježbe, treninga ili programa u retku ili kartici.
    static var itemTitle: Font { Font.system(.headline, design: .rounded, weight: .bold) }
    /// Naslov kartice verzalom uz ikonu (Početna). Ide uz `.textCase(.uppercase)`.
    static var cardHeading: Font { Font.system(.subheadline, design: .rounded, weight: .bold) }
    /// Mala oznaka verzalom: "Odmor", zaglavlje tablice serija, "Superset". Ide uz `.textCase(.uppercase)`.
    static var eyebrow: Font { Font.system(.caption, design: .rounded, weight: .bold) }

    // MARK: - Brojevi

    /// Najveći broj: odbrojavanje odmora, vrijednost na kotačiću.
    static var metricLarge: Font { Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit() }
    /// Istaknut broj na kartici: volumen tjedna, odbrojavanje na kartici treninga.
    static var metric: Font { Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit() }
    /// Manji istaknut broj: težina i ponavljanja u kartici treninga i Live Activity.
    static var metricSmall: Font { Font.system(.title3, design: .rounded, weight: .bold).monospacedDigit() }
    /// Vrijednost u polju za unos serije.
    static var fieldValue: Font { Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit() }
    /// Broj u retku liste: serija na detalju treninga, rekord.
    static var rowValue: Font { Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit() }
    /// Manji broj u retku: redni broj serije, prošli put, sljedeća serija.
    static var rowValueSmall: Font { Font.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit() }
}
