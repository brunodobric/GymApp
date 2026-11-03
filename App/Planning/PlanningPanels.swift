import Catalog
import Models
import Planning
import SwiftData
import SwiftUI

// Bočne ploče za slaganje treninga i rasporeda (faza 11). Na iPadu stoje uz uređivač kao inspector,
// a na iPhoneu se otvaraju kao list. Stavke se mogu odabrati više odjednom ili povući u uređivač.

/// Oznake za drag & drop: vježba nosi id sažetka ("c:…" ili "u:…"), a trening "t:<UUID>".
enum PlanningDrag {
    static func template(_ template: WorkoutTemplate) -> String { "t:\(template.id.uuidString)" }

    static func templateId(from payload: String) -> UUID? {
        guard payload.hasPrefix("t:") else { return nil }
        return UUID(uuidString: String(payload.dropFirst(2)))
    }
}

extension CatalogStore {
    /// Način unosa vježbe iz popisa (službene iz kataloga, vlastite iz baze).
    func inputType(of summary: ExerciseSummary, custom: [CustomExercise]) -> ExerciseInputType {
        switch summary.source {
        case .catalog(let id): catalog?.exercise(withID: id)?.inputType ?? .weightReps
        case .custom(let id): custom.first { $0.id == id }?.inputType ?? .weightReps
        }
    }

    /// Vježbe iz povučenih oznaka, redom povlačenja. Nepoznate oznake (npr. tekst iz druge aplikacije) se preskaču.
    func choices(from payloads: [String], custom: [CustomExercise]) -> [ExerciseChoice] {
        let all = summaries + custom.map(\.summary)
        return payloads.compactMap { payload in
            all.first { $0.id == payload }.map { ExerciseChoice(ref: $0.ref, inputType: inputType(of: $0, custom: custom)) }
        }
    }
}

/// Redak s kružićem odabira. Dodir mijenja odabir, a dugi pritisak povlači stavku.
struct SelectableRow<Label: View>: View {
    let isSelected: Bool
    let toggle: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Katalog uz uređivač treninga: pretraga, odabir više vježbi i povlačenje u popis vježbi.
struct ExerciseCatalogPanel: View {
    @Binding var isPresented: Bool
    let onAdd: ([ExerciseChoice]) -> Void

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]
    @State private var filter = ExerciseFilter()
    /// Odabrani id-evi sažetaka, redom odabira.
    @State private var selected: [String] = []

    private var results: [ExerciseSummary] {
        ExerciseSearch.apply(filter, to: catalogStore.summaries + customExercises.map(\.summary), labels: .app)
    }

    var body: some View {
        NavigationStack {
            List(results) { summary in
                SelectableRow(isSelected: selected.contains(summary.id), toggle: { toggle(summary) }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.name)
                        if let category = summary.category {
                            Text(category.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .draggable(summary.id) {
                    Label(summary.name, systemImage: "dumbbell")
                        .padding(8)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: filter.query) }
            }
            .navigationTitle("Katalog")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Pretraži vježbe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zatvori") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Dodaj" : "Dodaj (\(selected.count))") { add() }
                        .disabled(selected.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if sizeClass == .regular {
                    Text("Odaberi vježbe ili ih povuci u popis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.bar)
                }
            }
        }
    }

    private func toggle(_ summary: ExerciseSummary) {
        if let index = selected.firstIndex(of: summary.id) {
            selected.remove(at: index)
        } else {
            selected.append(summary.id)
        }
    }

    private func add() {
        onAdd(catalogStore.choices(from: selected, custom: customExercises))
        selected = []
        // Na iPhoneu je ploča list, pa se nakon dodavanja zatvara; na iPadu ostaje otvorena za daljnje slaganje.
        if sizeClass != .regular { isPresented = false }
    }
}

/// Treninzi uz uređivač rasporeda: odabir više treninga i povlačenje u niz.
struct TemplateListPanel: View {
    @Binding var isPresented: Bool
    let onAdd: ([WorkoutTemplate]) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var selected: [UUID] = []

    var body: some View {
        NavigationStack {
            List(templates) { template in
                SelectableRow(isSelected: selected.contains(template.id), toggle: { toggle(template) }) {
                    Label(template.name, systemImage: template.kind == .cardio ? "figure.run" : "dumbbell")
                }
                .draggable(PlanningDrag.template(template)) {
                    Label(template.name, systemImage: "dumbbell")
                        .padding(8)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "Još nema treninga", systemImage: "dumbbell",
                        description: Text("Treninzi se slažu u kartici Rasporedi.")
                    )
                }
            }
            .navigationTitle("Treninzi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zatvori") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Dodaj" : "Dodaj (\(selected.count))") { add() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func toggle(_ template: WorkoutTemplate) {
        if let index = selected.firstIndex(of: template.id) {
            selected.remove(at: index)
        } else {
            selected.append(template.id)
        }
    }

    private func add() {
        onAdd(selected.compactMap { id in templates.first { $0.id == id } })
        selected = []
        if sizeClass != .regular { isPresented = false }
    }
}
