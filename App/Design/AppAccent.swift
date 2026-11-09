import Models
import SwiftUI

extension EnvironmentValues {
    /// Naglasna boja iz Postavki kao `Color`, za mjesta koja trebaju boju, a ne stil
    /// (pozadine, grafovi, Canvas). Postavlja je `appAccent(_:)` zajedno s `.tint`.
    /// Na `Color.accentColor` se ne oslanjamo: to je AccentColor iz kataloga (u widgetu uvijek,
    /// vidi `LiveActivityAppearance`), a ne nužno korisnikov izbor.
    @Entry var appAccent: Color = AccentPalette.apolon
}

extension View {
    /// Naglasna boja iz Postavki: `.tint` za kontrole i `appAccent` za ostalo.
    func appAccent(_ choice: AccentChoice?) -> some View {
        let color = (choice ?? .blue).color
        return tint(color).environment(\.appAccent, color)
    }
}
