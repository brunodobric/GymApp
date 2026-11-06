import Models
import SwiftUI

/// Oznaka serije: veći redni broj radne serije ili narančasto "Z" za zagrijavanje, bez pozadine.
/// Dodirna površina je barem 44 × 44 pt (Apple HIG), a VoiceOver čita "Serija 2" ili "Zagrijavanje" umjesto slova.
struct SetBadge: View {
    let kind: SetKind
    /// Redni broj radne serije; zagrijavanje ga nema.
    let number: Int?

    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 30

    var body: some View {
        symbol
            .font(.metricSmall)
            .foregroundStyle(kind == .warmUp ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: size, minHeight: 44)
            .contentShape(.rect)
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
/// U tablici serija polje ima fiksnu širinu stupca (`setFieldWidth`), da su brojevi poravnati u svim retcima.
/// U tablici je polje visoko kao kvačica (`SetTableMetrics.rowHeight`), da je redak uredan.
struct SetFieldFrame: ViewModifier {
    @ScaledMetric(relativeTo: .title2) private var minWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .title2) private var maxWidth: CGFloat = 112
    @Environment(\.setFieldWidth) private var columnWidth
    private var metrics = SetTableMetrics()

    func body(content: Content) -> some View {
        content
            .font(.fieldValue)
            .multilineTextAlignment(.center)
            .frame(minWidth: columnWidth == nil ? minWidth : nil, maxWidth: columnWidth == nil ? maxWidth : nil)
            .padding(.horizontal, 6)
            .frame(width: columnWidth)
            .padding(.vertical, columnWidth == nil ? 6 : 0)
            .frame(minHeight: columnWidth == nil ? nil : metrics.rowHeight, maxHeight: columnWidth == nil ? nil : .infinity)
            .opaqueFill(.quaternary, in: .rect(cornerRadius: CornerRadius.inner))
    }
}

extension View {
    func setFieldFrame() -> some View {
        modifier(SetFieldFrame())
    }

    /// Prozirna ispuna na neprozirnoj podlozi boje retka. Boja aktivne serije iza retka (`listRowBackground`)
    /// tako ne prosijava kroz polja, oznaku i kvačicu, nego ostaje samo pozadina.
    func opaqueFill(_ style: some ShapeStyle, in shape: some Shape) -> some View {
        background(style, in: shape)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
    }
}

/// Širine stupaca tablice serija: oznaka, polja i kvačica. Dijele ih redak serije i zaglavlje tablice,
/// pa su stupci poravnati. Rastu s Dynamic Typeom.
struct SetTableMetrics: DynamicProperty {
    @ScaledMetric(relativeTo: .title3) var badge: CGFloat = 30
    /// Stupac "Prošli put": stalne širine, da su vrijednosti poravnate u svim retcima.
    @ScaledMetric(relativeTo: .subheadline) var previous: CGFloat = 68
    @ScaledMetric(relativeTo: .title2) var wideField: CGFloat = 76
    @ScaledMetric(relativeTo: .title2) var narrowField: CGFloat = 52
    @ScaledMetric(relativeTo: .title2) var check: CGFloat = 56
    /// Visina kvačice i polja u retku serije.
    @ScaledMetric(relativeTo: .title2) var rowHeight: CGFloat = 52
    /// Najmanji razmak među stupcima. Ostatak širine retka dijeli se jednako na sve razmake,
    /// pa su oznaka, prošli put, polja i kvačica podjednako udaljeni.
    let minGap: CGFloat = 4
}

private struct SetFieldWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Fiksna širina polja u tablici serija; bez nje polje raste sa sadržajem.
    var setFieldWidth: CGFloat? {
        get { self[SetFieldWidthKey.self] }
        set { self[SetFieldWidthKey.self] = newValue }
    }
}
