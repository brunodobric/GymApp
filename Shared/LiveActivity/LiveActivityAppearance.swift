import SwiftUI

/// Tema i naglasna boja Live Activityja iz stanja koje složi aplikacija.
/// Widget ne ovisi o GymKitu, pa se `AppTheme` i `AccentChoice` prenose kao tekst.
extension RestTimerActivityAttributes.ContentState {
    /// `nil` znači da Live Activity prati sistemsku temu.
    var colorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var accentColor: Color {
        AccentPalette.color(for: accent)
    }
}

extension EnvironmentValues {
    /// Naglasna boja Live Activityja. `Color.accentColor` u widgetu je uvijek zadana boja iz kataloga,
    /// pa dijelovi čitaju ovu vrijednost.
    @Entry var activityAccent: Color = AccentPalette.apolon
}
