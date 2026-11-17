import SwiftUI

/// Boje aplikacije (docs/DIZAJN.md, odjeljak Boja), zajedničke za aplikaciju, widgete, Live Activity i sat.
///
/// Paleta ima šest plavo-sivih tonova: #06141B, #11212D, #253745, #4A5C6A, #9BA8AB i #CCD0CF.
/// Tamna tema koristi samo njih, a svijetla dva izvedena tona (#E6E9E8 i #F7F8F8) za podlogu i kartice.
/// Akcent je jedan, Čelik: #253745 u svijetloj i #CCD0CF u tamnoj temi. Tekst na punom akcentu je
/// `onAccent` (bijeli odnosno #06141B), jer bijeli na svijetlom Čeliku ne bi bio čitljiv.
///
/// Kontrast teksta (WCAG) na kartici: primarni 17,6 : 1 i 10,6 : 1, sekundarni 6,5 : 1 i 6,7 : 1,
/// akcent 11,5 : 1 i 10,6 : 1. `separator` nije za tekst (ispod 3 : 1).
/// Zelena, narančasta i crvena ostaju semantičke (završena serija, zagrijavanje i rekord, brisanje).
enum AppPalette {
    /// Akcent Čelik: kontrole (`.tint`), istaknuti dijelovi, grafovi.
    static let accent = dynamic(light: 0x253745, dark: 0xCCD0CF)
    /// Tekst i simboli na punom akcentu (gumb, odabrani dan, broj aktivne serije).
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x06141B)
    /// Podloga ekrana (umjesto `systemGroupedBackground`).
    static let background = dynamic(light: 0xE6E9E8, dark: 0x06141B)
    /// Kartice i redovi popisa (umjesto `secondarySystemGroupedBackground`).
    static let card = dynamic(light: 0xF7F8F8, dark: 0x11212D)
    /// Ispuna: prazne točke, trake napretka, aktivna serija, sličice (umjesto `tertiarySystemFill`).
    static let fill = dynamic(light: 0xCCD0CF, dark: 0x253745)
    /// Blaža ispuna: polja i neodabrane opcije (umjesto `quaternarySystemFill`).
    static let subtleFill = dynamic(light: 0xE6E9E8, dark: 0x1A2C39)
    /// Razdjelnici i obrubi. Nije za tekst.
    static let separator = dynamic(light: 0x9BA8AB, dark: 0x4A5C6A)
    /// Primarni tekst.
    static let text = dynamic(light: 0x06141B, dark: 0xCCD0CF)
    /// Sekundarni tekst i ikone.
    static let secondaryText = dynamic(light: 0x4A5C6A, dark: 0x9BA8AB)

    /// Boja za `AccentChoice.rawValue` iz snimke widgeta ili stanja Live Activityja. Akcent je jedan,
    /// pa je vrijednost uvijek Čelik; funkcija ostaje da widgeti ne ovise o tome što je spremljeno.
    static func accent(for rawValue: String?) -> Color { accent }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(watchOS)
        // Sat je uvijek taman.
        color(dark)
        #else
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) })
        #endif
    }

    private static func components(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    #if os(watchOS)
    private static func color(_ hex: UInt32) -> Color {
        let rgb = components(hex)
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    #else
    static func uiColor(_ hex: UInt32) -> UIColor {
        let rgb = components(hex)
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
    #endif
}
