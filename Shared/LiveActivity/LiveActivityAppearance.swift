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

    var accentColor: Color { Self.accentColor(accent) }

    /// Boja za `AccentChoice.rawValue`. Treba je i alarm kraja odmora, koji nema stanje Live Activityja.
    static func accentColor(_ accent: String?) -> Color {
        switch accent {
        case "green": .green
        case "orange": .orange
        case "red": .red
        case "purple": .purple
        case "pink": .pink
        case "teal": .teal
        default: .blue
        }
    }
}

extension EnvironmentValues {
    /// Naglasna boja Live Activityja. `Color.accentColor` u widgetu je uvijek zadana boja iz kataloga,
    /// pa dijelovi čitaju ovu vrijednost.
    @Entry var activityAccent: Color = .blue
}
