import SwiftUI

/// Prikaz ili uređivanje stavke iz kartice Rasporedi (raspored, trening, kardio trening).
///
/// Otvorena stavka se prikazuje, a postavke (trajanje, aktivnost, podsjetnici, serije) mijenjaju se i tada.
/// Gumb Uredi uključuje promjenu naziva, redoslijeda, brisanje i dodavanje, a kvačica ga završava i sprema.
/// Dok se uređuje, natrag ide kroz `onLeave`, gdje kartica pita spremiti promjene ili izaći bez spremanja.
struct PlanningEditing {
    var isEditing: Bool
    var onEdit: () -> Void
    var onDone: () -> Void
    var onLeave: () -> Void
    /// Vlastiti natrag i u regular širini: za uređivač gurnut na stog, gdje sistemski natrag postoji
    /// u svakoj širini (u kartici Plan samo u compact širini, kad se split view sklopi).
    var replacesBackButtonAlways = false

    private var replacesBackButton: Bool { isEditing }

    func showsOwnBackButton(in sizeClass: UserInterfaceSizeClass?) -> Bool {
        replacesBackButton && (replacesBackButtonAlways || sizeClass == .compact)
    }
}

extension View {
    /// Dok se uređuje, lista je u načinu uređivanja: crtice za premještanje i znak za brisanje.
    /// Postavlja se na `List` uređivača.
    func planningEditMode(_ editing: PlanningEditing?) -> some View {
        environment(\.editMode, .constant(editing?.isEditing == true ? .active : .inactive))
    }

    /// Gumbi Uredi, kvačica i natrag za uređivač. Bez `editing` (uređivač otvoren izvan kartice Rasporedi,
    /// npr. novi trening iz rasporeda ili iz povijesti) uređivač je uvijek u uređivanju i bez tih gumba.
    func planningEditToolbar(_ editing: PlanningEditing?) -> some View {
        modifier(PlanningEditToolbar(editing: editing))
    }
}

private struct PlanningEditToolbar: ViewModifier {
    let editing: PlanningEditing?
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if let editing {
            content
                // Sistemski natrag bi izašao bez pitanja, pa uređivanje ima svoj (i bez povlačenja s ruba).
                .navigationBarBackButtonHidden(editing.showsOwnBackButton(in: sizeClass))
                .toolbar {
                    if editing.isEditing {
                        if editing.showsOwnBackButton(in: sizeClass) {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Natrag", systemImage: "chevron.left", action: editing.onLeave)
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Gotovo", systemImage: "checkmark", action: editing.onDone)
                        }
                    } else {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Uredi", action: editing.onEdit)
                        }
                    }
                }
        } else {
            content
        }
    }
}
