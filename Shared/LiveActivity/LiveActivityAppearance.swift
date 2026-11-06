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

extension View {
    /// Na zaključanom zaslonu: vlastita pozadina i shema boja kad tema nije "Sustav".
    /// Dynamic Island je uvijek crn, pa se ondje primjenjuje samo naglasna boja.
    @ViewBuilder
    func lockScreenAppearance(_ state: RestTimerActivityAttributes.ContentState) -> some View {
        let accented = environment(\.activityAccent, state.accentColor)
        switch state.colorScheme {
        case .light:
            accented
                .environment(\.colorScheme, .light)
                .activityBackgroundTint(Color.white.opacity(0.9))
                .activitySystemActionForegroundColor(.black)
        case .dark:
            accented
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        default:
            accented
        }
    }
}
