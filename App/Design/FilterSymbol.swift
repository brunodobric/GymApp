import SwiftUI

/// Simbol gumba za filtriranje u toolbaru, isti na svim ekranima.
/// Bez filtera je to obični simbol (bez kruga), jednak gumbu + do njega: simbol s krugom u
/// Liquid Glass gumbu izgleda kao dvostruki krug, a hijerarhijski sloj kruga ga čini blijedim.
/// S uključenim filterom krug je pun, pa se odmah vidi da je filter uključen.
enum FilterSymbol {
    static func name(isActive: Bool) -> String {
        isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease"
    }
}

extension View {
    /// Simbol filtera (i drugih izbornika u toolbaru) crta se jednobojno u primarnoj boji,
    /// kao ostali gumbi u toolbaru.
    func filterSymbolStyle() -> some View {
        symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
    }
}
