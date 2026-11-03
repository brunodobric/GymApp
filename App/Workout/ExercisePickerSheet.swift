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

    private var results: [ExerciseSummary] {
        ExerciseSearch.apply(filter, to: catalogStore.summaries + customExercises.map(\.summary), labels: .app)
    }

    var body: some View {
        NavigationStack {
            List(results) { summary in
                Button {
                    onPick(summary, inputType(of: summary))
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

    private func inputType(of summary: ExerciseSummary) -> ExerciseInputType {
        switch summary.source {
        case .catalog(let id): catalogStore.catalog?.exercise(withID: id)?.inputType ?? .weightReps
        case .custom(let id): customExercises.first { $0.id == id }?.inputType ?? .weightReps
        }
    }
}
