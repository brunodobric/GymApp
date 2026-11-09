import SwiftUI

/// Naglasne boje aplikacije (docs/DIZAJN.md, odjeljak Boja), zajedničke za aplikaciju, widgete,
/// Live Activity i sat.
///
/// Boja se bira po tekstu (`AccentChoice.rawValue` u GymKitu), jer widgeti ne ovise o GymKitu.
/// Svaka boja ima svijetlu i tamnu vrijednost: obje imaju barem 4,5 : 1 kao tekst na podlozi
/// (bijela odnosno `secondarySystemGroupedBackground`), a bijeli tekst na punom gumbu barem 3 : 1.
/// Zelena, crvena i narančasta nisu u ponudi jer znače završenu seriju, brisanje i zagrijavanje.
enum AccentPalette {
    /// Zadana boja, "Apolon plava": nijansa podloge ikone, svjetlija da bude čitljiva.
    /// Ista je i u `AccentColor` u katalozima aplikacije i sata.
    static let apolon = dynamic(light: 0x1F5BD6, dark: 0x4C88FA)

    /// Boja za `AccentChoice.rawValue`. Nepoznata vrijednost (i stare "green", "orange", "red") je zadana.
    static func color(for rawValue: String?) -> Color {
        switch rawValue {
        case "indigo": dynamic(light: 0x4B47D6, dark: 0x7F7AF7)
        case "purple": dynamic(light: 0x8A3CCB, dark: 0xA66CEB)
        case "pink": dynamic(light: 0xC8255F, dark: 0xEA4F8B)
        case "teal": dynamic(light: 0x00707F, dark: 0x1A98A7)
        case "graphite": dynamic(light: 0x3A404C, dark: 0x868C98)
        default: apolon
        }
    }

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
    private static func uiColor(_ hex: UInt32) -> UIColor {
        let rgb = components(hex)
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
    #endif
}
