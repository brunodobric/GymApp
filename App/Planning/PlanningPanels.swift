import Catalog
import Models
import Planning
import SwiftData
import SwiftUI
import Training

// Bočne ploče za slaganje treninga i rasporeda (faza 11). Na iPadu stoje uz uređivač kao inspector,
// a na iPhoneu se otvaraju kao list. Stavke se mogu odabrati više odjednom, a na iPadu i povući u uređivač.

/// Oznake za drag & drop: vježba nosi id sažetka ("c:…" ili "u:…"), a trening "t:<UUID>".
enum PlanningDrag {
    static func template(_ template: WorkoutTemplate) -> String { "t:\(template.id.uuidString)" }

    static func templateId(from payload: String) -> UUID? {
        guard payload.hasPrefix("t:") else { return nil }
        return UUID(uuidString: String(payload.dropFirst(2)))
    }
}

extension CatalogStore {
    /// Službene i vlastite vježbe koje prolaze filter (pretraga i filteri), za sve popise vježbi.
    func search(_ filter: ExerciseFilter, custom: [CustomExercise]) -> [ExerciseSummary] {
        ExerciseSearch.apply(filter, to: summaries + custom.map(\.summary), labels: .app)
    }

    /// Rezultati pretrage s odabranim vježbama na vrhu (`ExerciseSearch.pinningSelected`).
    func pinningSelected(
        _ selected: [String], results: [ExerciseSummary], custom: [CustomExercise]
    ) -> (selected: [ExerciseSummary], others: [ExerciseSummary]) {
        guard !selected.isEmpty else { return ([], results) }
        return ExerciseSearch.pinningSelected(selected, results: results, all: summaries + custom.map(\.summary))
    }

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

extension View {
    /// Prečac ⌘ + `key` koji radi bez obzira na to je li gumb s istom radnjom na ekranu. `List` gradi retke
    /// lijeno, pa prečac na gumbu pri dnu dugog popisa ne radi dok korisnik ne skrolira do njega.
    /// Gumb je nevidljiv, a naziv se vidi u popisu prečaca (držanje tipke ⌘ na iPadu).
    func commandShortcut(_ title: LocalizedStringKey, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        background {
            Button(title, action: action)
                .keyboardShortcut(key, modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Bočna ploča uređivača: na iPadu (regular širina) inspector uz sadržaj, a na iPhoneu obični list.
    ///
    /// U compact širini se `.inspector` uopće ne primjenjuje. Inače njegov sadržaj ostaje ugrađen u uređivač
    /// i kad je ploča zatvorena: alatna traka i pretraga ploče spoje se s navigacijskom trakom uređivača, pa
    /// se ondje vide drugi gumbi Zatvori i Dodaj koji ne rade (Zatvori ne zatvara ništa, a Dodaj se nikad
    /// ne omogući jer ta kopija ploče ima svoj odabir).
    func planningPanel<Panel: View>(
        isPresented: Binding<Bool>,
        minWidth: CGFloat,
        idealWidth: CGFloat,
        maxWidth: CGFloat,
        @ViewBuilder panel: @escaping () -> Panel
    ) -> some View {
        modifier(PlanningPanelModifier(
            isPresented: isPresented, minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth, panel: panel
        ))
    }

    /// Povlačenje stavke iz ploče, samo kad ploča stoji uz uređivač (iPad). Na iPhoneu list prekriva
    /// uređivač pa povlačenje nema kamo, a dugi pritisak na redak samo smeta dodiru za odabir.
    @ViewBuilder
    func panelDraggable(_ payload: String, enabled: Bool, title: String, systemImage: String) -> some View {
        if enabled {
            draggable(payload) {
                Label(title, systemImage: systemImage)
                    .padding(8)
                    .background(.regularMaterial, in: .rect(cornerRadius: CornerRadius.small))
            }
        } else {
            self
        }
    }
}

private struct PlanningPanelModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat
    @ViewBuilder let panel: () -> Panel

    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.inspector(isPresented: $isPresented) {
                panel().inspectorColumnWidth(min: minWidth, ideal: idealWidth, max: maxWidth)
            }
        } else {
            content.sheet(isPresented: $isPresented) { panel() }
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

    var body: some View {
        // Pretraga se računa jednom po iscrtavanju (oko 800 vježbi).
        let results = catalogStore.search(filter, custom: customExercises)
        // Tijekom pretrage odabrane vježbe stoje na vrhu, da korisnik vidi što je već odabrao.
        let isQuerying = !filter.query.trimmingCharacters(in: .whitespaces).isEmpty
        let pinned = isQuerying
            ? catalogStore.pinningSelected(selected, results: results, custom: customExercises)
            : (selected: [], others: results)
        NavigationStack {
            List {
                if pinned.selected.isEmpty {
                    rows(pinned.others)
                } else {
                    Section("Odabrano") { rows(pinned.selected) }
                    if !pinned.others.isEmpty {
                        Section("Rezultati") { rows(pinned.others) }
                    }
                }
            }
            .accessibilityIdentifier("planningPanel.list")
            .overlay {
                if results.isEmpty && pinned.selected.isEmpty { ContentUnavailableView.search(text: filter.query) }
            }
            .safeAreaInset(edge: .bottom) {
                CatalogPanelBottomBar(
                    selectedCount: selected.count, showsDragHint: sizeClass == .regular, add: add
                )
            }
            .navigationTitle("Katalog")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Pretraži vježbe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zatvori") { isPresented = false }
                        .accessibilityIdentifier("planningPanel.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Dodaj" : "Dodaj (\(selected.count))") { add() }
                        .disabled(selected.isEmpty)
                        .accessibilityIdentifier("planningPanel.add")
                }
            }
        }
    }

    private func rows(_ summaries: [ExerciseSummary]) -> some View {
        ForEach(summaries) { summary in
            SelectableRow(isSelected: selected.contains(summary.id), toggle: { toggle(summary) }) {
                ExerciseRowThumbnail(
                    source: catalogStore.thumbnail(for: summary.source, customExercises: customExercises)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name)
                    if let category = summary.category {
                        Text(category.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .panelDraggable(summary.id, enabled: sizeClass == .regular, title: summary.name, systemImage: "dumbbell")
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

/// Donja traka kataloga. Dok je pretraga aktivna, sustav skriva navigacijsku traku s gumbom Dodaj,
/// pa se gumb tada prikazuje ovdje, iznad tipkovnice. Na iPadu traka nosi i uputu za povlačenje.
private struct CatalogPanelBottomBar: View {
    let selectedCount: Int
    let showsDragHint: Bool
    let add: () -> Void

    @Environment(\.isSearching) private var isSearching

    var body: some View {
        if isSearching || showsDragHint {
            VStack(spacing: 8) {
                if isSearching {
                    Button(action: add) {
                        Label(selectedCount == 0 ? "Dodaj" : "Dodaj (\(selectedCount))", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedCount == 0)
                    .accessibilityIdentifier("planningPanel.addWhileSearching")
                }
                if showsDragHint {
                    Text("Odaberi vježbe ili ih povuci u popis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.bar)
        }
    }
}

/// Treninzi uz uređivač rasporeda: odabir više treninga i povlačenje u niz.
struct TemplateListPanel: View {
    @Binding var isPresented: Bool
    let onAdd: ([WorkoutTemplate]) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @Query private var customExercises: [CustomExercise]
    @Environment(CatalogStore.self) private var catalogStore
    @State private var selected: [UUID] = []

    var body: some View {
        NavigationStack {
            List(templates) { template in
                SelectableRow(isSelected: selected.contains(template.id), toggle: { toggle(template) }) {
                    Label {
                        Text(template.name)
                            .font(.itemTitle)
                    } icon: {
                        WorkoutKindIcon(
                            mix: SessionCardio.mix(of: template, isCardio: catalogStore.isCardio(custom: customExercises))
                        )
                    }
                }
                .panelDraggable(
                    PlanningDrag.template(template), enabled: sizeClass == .regular,
                    title: template.name, systemImage: "dumbbell"
                )
            }
            .accessibilityIdentifier("planningPanel.list")
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
                        .accessibilityIdentifier("planningPanel.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Dodaj" : "Dodaj (\(selected.count))") { add() }
                        .disabled(selected.isEmpty)
                        .accessibilityIdentifier("planningPanel.add")
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
