import SwiftUI

extension EnvironmentValues {
    /// Akcent kao `Color`, za mjesta koja trebaju boju, a ne stil (pozadine, grafovi, Canvas).
    /// Postavlja ga `appPalette()` zajedno s `.tint`. Na `Color.accentColor` se ne oslanjamo:
    /// to je AccentColor iz kataloga (u widgetu uvijek, vidi `LiveActivityAppearance`).
    @Entry var appAccent: Color = AppPalette.accent
}

extension View {
    /// Boje aplikacije na korijenu prozora ili lista: akcent Čelik (`.tint` za kontrole i `appAccent`
    /// za ostalo) te primarni i sekundarni tekst iz palete umjesto sistemskih.
    func appPalette() -> some View {
        tint(AppPalette.accent)
            .environment(\.appAccent, AppPalette.accent)
            .foregroundStyle(AppPalette.text, AppPalette.secondaryText, AppPalette.secondaryText.opacity(0.75))
    }

    /// Podloga popisa (`List`, `Form`) iz palete umjesto sistemske. Redovi dobivaju boju kartice
    /// preko `listRowBackground` unutar popisa.
    func appListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppPalette.background.ignoresSafeArea())
    }

    /// Boja retka u popisu s odabirom (stupac lijevo na iPadu): kartica, a odabrani redak akcent preko nje.
    /// Vlastita boja retka skriva sistemsko isticanje odabira, pa se odabir boji ovdje.
    func selectableRowBackground(_ isSelected: Bool) -> some View {
        listRowBackground(AppPalette.accent.opacity(isSelected ? 0.18 : 0).background(AppPalette.card))
    }
}
