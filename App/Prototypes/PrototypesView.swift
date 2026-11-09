#if DEBUG
import SwiftUI

/// Alati za razvoj (zasad alat za CloudKit shemu, `docs/sinkronizacija.md`). Postoji samo u Debug buildu.
struct PrototypesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CloudKitSchemaToolView()
                } label: {
                    Label("CloudKit shema", systemImage: "icloud")
                }
            }
            .navigationTitle("Prototipi")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
        }
    }
}
#endif
