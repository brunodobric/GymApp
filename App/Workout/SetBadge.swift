import Models
import SwiftUI

/// Oznaka serije u krugu: redni broj radne serije ili "Z" za zagrijavanje.
/// Krug raste s Dynamic Typeom, a VoiceOver čita "Serija 2" ili "Zagrijavanje" umjesto slova.
struct SetBadge: View {
    let kind: SetKind
    /// Redni broj radne serije; zagrijavanje ga nema.
    let number: Int?

    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 30

    var body: some View {
        symbol
            .font(.subheadline.bold())
            .frame(minWidth: size, minHeight: size)
            .background(kind == .warmUp ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.15), in: .circle)
            .accessibilityLabel(label)
    }

    /// "Z" je kratica za zagrijavanje i prevodi se ("W" na engleskom).
    private var symbol: Text {
        if kind != .warmUp, let number { return Text(verbatim: "\(number)") }
        return Text("Z")
    }

    private var label: Text {
        if kind != .warmUp, let number { return Text("Serija \(number)") }
        return Text("Zagrijavanje")
    }
}

/// Okvir polja za unos u retku serije: velik, podebljan broj da se vrijednost vidi i iz daljine.
/// Širina raste s Dynamic Typeom, da broj ne bude odrezan.
struct SetFieldFrame: ViewModifier {
    @ScaledMetric(relativeTo: .title2) private var minWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .title2) private var maxWidth: CGFloat = 112

    func body(content: Content) -> some View {
        content
            .font(.title2.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(minWidth: minWidth, maxWidth: maxWidth)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(.quaternary, in: .rect(cornerRadius: CornerRadius.inner))
    }
}

extension View {
    func setFieldFrame() -> some View {
        modifier(SetFieldFrame())
    }
}
