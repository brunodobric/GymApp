import Catalog
import Models
import SwiftData
import SwiftUI

/// Odabir vježbe za trening: katalog i vlastite vježbe, s pretragom.
struct ExercisePickerSheet: View {
    let title: LocalizedStringKey
    let onPick: (ExerciseSummary, ExerciseInputType) -> Void

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]
    @State private var filter = ExerciseFilter()

    var body: some View {
        // Pretraga se računa jednom po iscrtavanju (oko 800 vježbi).
        let results = catalogStore.search(filter, custom: customExercises)
        NavigationStack {
            List(results) { summary in
                Button {
                    onPick(summary, catalogStore.inputType(of: summary, custom: customExercises))
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.name)
                        if let category = summary.category {
                            Text(category.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: filter.query) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.query, prompt: "Pretraži vježbe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Odustani") { dismiss() }
                }
            }
        }
    }
}
