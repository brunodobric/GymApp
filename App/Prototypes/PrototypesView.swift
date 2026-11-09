#if DEBUG
import SwiftUI

/// Alati za razvoj (zasad alat za CloudKit shemu, `docs/sinkronizacija.md`). Postoji samo u Debug buildu.
/// Tekstovi su doslovni (`String`, `verbatim:`) i ne idu u String Catalog (`docs/lokalizacija.md`).
struct PrototypesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CloudKitSchemaToolView()
                } label: {
                    Label(String("CloudKit shema"), systemImage: "icloud")
                }
            }
            .navigationTitle(String("Prototipi"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
        }
    }
}
#endif
