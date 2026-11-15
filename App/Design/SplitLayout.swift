import SwiftUI

/// Podijeljeni prikaz taba: popis ili kartice lijevo, detalj desno.
///
/// Koristi se u regular širini: iPad, iPhone u vodoravnom položaju i unutarnji zaslon otvorenog
/// iPhonea Duo. Oba stupca su uvijek vidljiva (`.balanced`, bez gumba za skrivanje bočnog stupca),
/// pa se i uspravni otvoreni zaslon dijeli na lijevu i desnu stranu, umjesto da se jedan stupac razvuče.
/// U compact širini (vanjski zaslon, iPhone uspravno) sustav sklapa prikaz u jedan stupac (Apple HIG, iPhone Duo).
struct TabSplitView<Sidebar: View, Detail: View>: View {
    /// Željena širina lijevog stupca. Zadana odgovara popisu; aktivni trening daje više mjesta videu vježbe.
    var sidebarWidth: CGFloat = 380
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var detail: Detail

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: sidebarWidth - 60, ideal: sidebarWidth, max: sidebarWidth + 80)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// Odabir u desnom stupcu podijeljenog prikaza. Postoji samo dok je tab podijeljen (regular širina).
struct DetailSelection {
    /// Što je trenutno u desnom stupcu (i zadani detalj kad korisnik još ništa nije odabrao).
    var selected: AnyHashable?
    var select: (AnyHashable) -> Void
}

extension EnvironmentValues {
    // swiftlint:disable:next redundant_optional_initialization
    @Entry var detailSelection: DetailSelection? = nil
}

/// Poveznica s kartice na ekran detalja.
///
/// U jednom stupcu (compact) gura ekran u stog kao `NavigationLink(value:)`, pa tab mora imati
/// `navigationDestination` za tip vrijednosti. U podijeljenom prikazu otvara ekran u desnom stupcu,
/// a odabrana kartica ostaje označena (Apple HIG, split views).
struct DetailLink<Value: Hashable, Label: View>: View {
    let value: Value
    /// Zaobljenje oznake odabira: kartica ili redak unutar kartice.
    var cornerRadius: CGFloat = CornerRadius.card
    /// Koliko oznaka odabira izlazi izvan sadržaja (redak unutar kartice nema vlastiti razmak).
    var outset: CGFloat = 0
    @ViewBuilder var label: Label

    @Environment(\.detailSelection) private var selection

    var body: some View {
        if let selection {
            let isSelected = selection.selected == AnyHashable(value)
            Button {
                selection.select(value)
            } label: {
                label
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.tint, lineWidth: 2)
                        .padding(-outset)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            NavigationLink(value: value) { label }
        }
    }
}
