#if DEBUG
import SwiftUI

/// Ulaz u prototipe iz faze 0 i alate za razvoj. Postoji samo u Debug buildu.
/// Postupak provjere i mjesto za upis nalaza: docs/prototipi.md.
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
                NavigationLink {
                    WorkoutKitPrototypeView()
                } label: {
                    Label("WorkoutKit zakazivanje", systemImage: "figure.run")
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
