import Catalog
import Models
import SwiftData
import SwiftUI

/// Odabir vježbe za trening: katalog i vlastite vježbe, s pretragom i filterom dijela tijela.
/// Bez upita na vrhu su prijedlozi (zamjena vježbe) i nedavne vježbe. S `allowsMultiple` se odabire
/// više vježbi odjednom, a `onPick` se zove za svaku redom odabira.
struct ExercisePickerSheet: View {
    let title: LocalizedStringKey
    var allowsMultiple = false
    /// Prijedlozi na vrhu (npr. zamjene za zauzetu spravu, `ExerciseSearch.alternatives`).
    var suggested: [ExerciseSummary] = []
    /// Ključevi nedavnih vježbi (`GymQueries.recentExerciseKeys`), od najnovije.
    var recentKeys: [String] = []
    /// Vježbe koje se ne nude među nedavnima (već su u treningu).
    var excludedKeys: Set<String> = []
    let onPick: (ExerciseSummary, ExerciseInputType) -> Void

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]
    @State private var filter = ExerciseFilter()
    /// Odabrane vježbe (id iz `ExerciseSummary.id`) redom odabira.
    @State private var selected: [String] = []

    var body: some View {
        // Pretraga se računa jednom po iscrtavanju (oko 800 vježbi).
        let results = catalogStore.search(filter, custom: customExercises)
        let showsShortcuts = filter.query.isEmpty && filter.categories.isEmpty
        let suggestions = showsShortcuts ? suggested : []
        let recent = showsShortcuts
            ? ExerciseSearch.recent(
                recentKeys, in: catalogStore.summaries + customExercises.map(\.summary),
                excluding: excludedKeys.union(suggestions.map(\.id))
            )
            : []
        NavigationStack {
            List {
                Section { categoryChips }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                if !suggestions.isEmpty {
                    Section("Prijedlozi") { ForEach(suggestions) { row($0) } }
                }
                if !recent.isEmpty {
                    Section("Nedavno") { ForEach(recent) { row($0) } }
                }
                Section {
                    ForEach(results) { row($0) }
                } header: {
                    if !suggestions.isEmpty || !recent.isEmpty { Text("Sve vježbe") }
                }
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
                if allowsMultiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Dodaj (\(selected.count))", action: addSelected)
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }

    /// Dijelovi tijela kao gumbi u nizu: dodir uključuje i isključuje filter.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    let isOn = filter.categories.contains(category)
                    Button {
                        if isOn { filter.categories.remove(category) } else { filter.categories.insert(category) }
                    } label: {
                        Text(category.title)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(isOn ? .accentColor : .secondary)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func row(_ summary: ExerciseSummary) -> some View {
        let isSelected = selected.contains(summary.id)
        return Button {
            if allowsMultiple {
                if isSelected { selected.removeAll { $0 == summary.id } } else { selected.append(summary.id) }
            } else {
                onPick(summary, catalogStore.inputType(of: summary, custom: customExercises))
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                ExerciseRowThumbnail(source: catalogStore.thumbnail(for: summary.source, customExercises: customExercises))
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name)
                    details(of: summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if allowsMultiple {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Dio tijela i oprema, npr. "Prsa · Bučice".
    @ViewBuilder
    private func details(of summary: ExerciseSummary) -> some View {
        HStack(spacing: 4) {
            if let category = summary.category { Text(category.title) }
            if summary.category != nil, summary.equipment != nil { Text(verbatim: "·") }
            if let equipment = summary.equipment { Text(equipment.title) }
        }
    }

    private func addSelected() {
        let all = catalogStore.summaries + customExercises.map(\.summary)
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in selected {
            guard let summary = byID[id] else { continue }
            onPick(summary, catalogStore.inputType(of: summary, custom: customExercises))
        }
        dismiss()
    }
}
