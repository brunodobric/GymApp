import Models
import Stats
import SwiftData
import SwiftUI

/// Uključivanje i isključivanje pojedinih vježbi iz rekorda. Popis su vježbe iz odrađenih treninga.
/// Isključena vježba nema rekorda ni u sažetku treninga ni u statistici, a povijest ostaje.
struct RecordExercisesScreen: View {
    @Bindable var settings: UserSettings

    @Environment(\.modelContext) private var context
    /// Vježbe se učitaju jednom pri otvaranju, a pretraga filtrira taj popis.
    @State private var done: [DoneExercise] = []
    @State private var search = ""

    private var items: [DoneExercise] {
        search.isEmpty ? done : done.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                if items.isEmpty {
                    Text("Nema vježbi za prikaz.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Toggle(item.name, isOn: Binding(
                        get: { !settings.prExcludedExerciseKeys.contains(item.key) },
                        set: { settings.setRecordsEnabled($0, forExercise: item.key) }
                    ))
                }
            } footer: {
                Text("Isključi vježbe za koje ne želiš rekorde, npr. zagrijavanje ili vježbe koje radiš samo za tehniku.")
            }
        }
        .navigationTitle("Vježbe u rekordima")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Vježba")
        .task { done = (try? DoneExercises.fetch(in: context)) ?? [] }
    }
}
