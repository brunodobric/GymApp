import Catalog
import Models
import SwiftData
import SwiftUI

/// Tab Vježbe: službeni katalog i vlastite vježbe u jednom popisu, s pretragom i filterima.
///
/// U regular širini (iPad) katalog je mreža sa slikama, a u compact širini popis.
struct ExercisesScreen: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var filter = ExerciseFilter()
    @State private var showsFilters = false
    @State private var showsNewExercise = false

    var body: some View {
        // Pretraga se računa jednom po iscrtavanju (oko 800 vježbi).
        let results = catalogStore.search(filter, custom: customExercises)
        NavigationStack {
            content(results)
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
    private func content(_ results: [ExerciseSummary]) -> some View {
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
        } else if sizeClass == .regular {
            grid(results)
        } else {
            List(results) { summary in
                NavigationLink(value: summary) {
                    ExerciseRow(summary: summary)
                }
                .openInWindowMenu(DetailWindow.exercise, value: summary.id)
            }
        }
    }

    private func grid(_ results: [ExerciseSummary]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(results) { summary in
                    NavigationLink(value: summary) {
                        ExerciseGridCell(summary: summary, thumbnail: thumbnail(for: summary))
                    }
                    .buttonStyle(.plain)
                    .openInWindowMenu(DetailWindow.exercise, value: summary.id)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func thumbnail(for summary: ExerciseSummary) -> ExerciseThumbnail.Source? {
        switch summary.source {
        case .catalog:
            return catalogStore.thumbnail(for: summary)
        case .custom(let id):
            guard let data = customExercises.first(where: { $0.id == id })?.imageData else { return nil }
            return .data(key: id.uuidString, data)
        }
    }
}

/// Ćelija mreže kataloga: slika, naziv te kategorija i oprema.
private struct ExerciseGridCell: View {
    let summary: ExerciseSummary
    let thumbnail: ExerciseThumbnail.Source?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExerciseThumbnail(source: thumbnail)
            Text(summary.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 14))
        .hoverEffect()
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if let category = summary.category { parts.append(String(localized: category.title)) }
        if let equipment = summary.equipment { parts.append(String(localized: equipment.title)) }
        if summary.isCustom {
            parts.append(summary.isArchived ? String(localized: "Arhivirana") : String(localized: "Vlastita"))
        }
        return parts.joined(separator: " · ")
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
