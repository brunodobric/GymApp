import Catalog
import Models
import SwiftData
import SwiftUI

/// Tab Vježbe: službeni katalog i vlastite vježbe u jednom popisu, s pretragom i filterima.
struct ExercisesScreen: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var filter = ExerciseFilter()
    @State private var showsFilters = false
    @State private var showsNewExercise = false

    private var results: [ExerciseSummary] {
        ExerciseSearch.apply(filter, to: catalogStore.summaries + customExercises.map(\.summary))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Vježbe")
                .navigationDestination(for: ExerciseSummary.self) { summary in
                    ExerciseDetailScreen(summary: summary)
                }
                .searchable(text: $filter.query, prompt: "Pretraži vježbe")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Filteri", systemImage: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle") {
                            showsFilters = true
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Nova vježba", systemImage: "plus") {
                            showsNewExercise = true
                        }
                    }
                }
                .sheet(isPresented: $showsFilters) {
                    ExerciseFilterSheet(filter: $filter)
                }
                .sheet(isPresented: $showsNewExercise) {
                    CustomExerciseEditor(exercise: nil)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorText = catalogStore.errorText {
            ContentUnavailableView(
                "Katalog nije dostupan",
                systemImage: "exclamationmark.triangle",
                description: Text(errorText)
            )
        } else if results.isEmpty {
            if filter.query.isEmpty {
                ContentUnavailableView(
                    "Nema vježbi",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Nijedna vježba ne odgovara odabranim filterima.")
                )
            } else {
                ContentUnavailableView.search(text: filter.query)
            }
        } else {
            List(results) { summary in
                NavigationLink(value: summary) {
                    ExerciseRow(summary: summary)
                }
            }
        }
    }
}

private struct ExerciseRow: View {
    let summary: ExerciseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.name)
            HStack(spacing: 4) {
                if let category = summary.category {
                    Text(category.title)
                }
                if let equipment = summary.equipment {
                    Text("·")
                    Text(equipment.title)
                }
                if summary.isCustom {
                    Text("·")
                    Text(summary.isArchived ? "Arhivirana" : "Vlastita")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
