import CoreGraphics

/// Polumjeri zaobljenja u aplikaciji (iPhone i iPad). Kutovi su koncentrični:
/// unutarnji element ima manji polumjer od kartice u kojoj stoji (vanjski polumjer − razmak).
/// Oblik je uvijek `continuous` (zadano u SwiftUI-ju), kao na sistemskim karticama.
enum CornerRadius {
    /// Kartice na Početnoj, u statistici i katalogu, u skladu sa sekcijama listi na iOS 26.
    static let card: CGFloat = 24
    /// Elementi unutar kartice: polja za unos, kvačica serije, sličica vježbe, retci u onboardingu.
    static let inner: CGFloat = 12
    /// Sitni elementi: dan u kalendaru, oznaka u panelu, gumbi − i + u kartici treninga.
    static let small: CGFloat = 8
    /// Plutajuće trake pri dnu ekrana (odmor, poništavanje).
    static let floating: CGFloat = 28
}
