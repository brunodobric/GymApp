import Catalog
import Models
import SwiftData
import SwiftUI

/// Odredište s početne kataloga: popis jedne vrste, svih vježbi ili samo vlastitih.
enum ExerciseListRoute: Hashable {
    case kind(ExerciseKind)
    case all
    case custom

    var title: LocalizedStringResource {
        switch self {
        case .kind(let kind): kind.title
        case .all: "Sve vježbe"
        case .custom: "Moje vježbe"
        }
    }

    /// Filter s kojim se popis otvara. Vrsta i izvor ostaju i kad korisnik poništi filtere.
    var initialFilter: ExerciseFilter {
        switch self {
        case .kind(let kind): ExerciseFilter(kinds: [kind])
        case .all: ExerciseFilter()
        case .custom: ExerciseFilter(kinds: [], origin: .custom)
        }
    }
}

/// Tab Vježbe. Početna su kartice vrsta (zagrijavanje, snaga, istezanje, kardio) i poveznice na sve
/// i vlastite vježbe. Pretraga ili filter odmah prikazuju rezultate iz cijelog kataloga.
///
/// U regular širini (iPad, otvoreni iPhone Duo) lijevo je popis vježbi s odabirom vrste, a desno
/// odabrana vježba. Dok vježba nije odabrana, desno su kartice vrsta, koje mijenjaju popis lijevo.
struct ExercisesScreen: View {
    /// Mijenja se kad korisnik ponovno dodirne već otvoren tab: stog navigacije se vraća na korijen.
    var rootReset = 0

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var filter = ExerciseFilter()
    @State private var showsFilters = false
    @State private var showsNewExercise = false
    @State private var path = NavigationPath()
    /// Zadnja otvorena vježba i popis. Dijele ih oba rasporeda, pa preklapanje i otvaranje iPhonea Duo
    /// zadržava otvorenu vježbu (desni stupac odnosno vrh stoga).
    @State private var selection: ExerciseSummary.Source?
    @State private var route: ExerciseListRoute = .all

    var body: some View {
        Group {
            if sizeClass == .regular {
                TabSplitView {
                    ExerciseSplitList(route: $route, selection: $selection)
                } detail: {
                    NavigationStack {
                        if let selection {
                            ExerciseDetailScreen(source: selection)
                        } else {
                            ExerciseKindHome(customExercises: customExercises) { route = $0 }
                                .navigationTitle("Vrste vježbi")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    // Nova vježba počinje s praznim stogom.
                    .id(selection)
                }
            } else {
                stack
            }
        }
        // Preklapanje: otvoreni popis i vježba iz desnog stupca postaju stog.
        .onChange(of: sizeClass) { _, newValue in
            guard newValue == .compact else { return }
            path = compactPath
        }
        .onChange(of: rootReset) {
            path = NavigationPath()
            selection = nil
            route = .all
        }
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            Group {
                if filter.query.isEmpty && !filter.isActive && catalogStore.errorText == nil {
                    ExerciseKindHome(customExercises: customExercises)
                } else {
                    // Pretraga se računa jednom po iscrtavanju (oko 800 vježbi).
                    ExerciseResults(
                        results: catalogStore.search(filter, custom: customExercises),
                        query: filter.query,
                        customExercises: customExercises
                    )
                }
            }
            .navigationTitle("Vježbe")
            .navigationDestination(for: ExerciseSummary.self) { summary in
                ExerciseDetailScreen(summary: summary)
                    .onAppear { selection = summary.source }
            }
            .navigationDestination(for: ExerciseListRoute.self) { route in
                ExerciseListScreen(route: route)
                    .onAppear { self.route = route }
            }
            .searchable(text: $filter.query, prompt: "Pretraži vježbe")
            .toolbar {
                ExerciseListToolbar(isFiltered: filter.isActive, showsFilters: $showsFilters, showsNewExercise: $showsNewExercise)
            }
            .sheet(isPresented: $showsFilters) {
                ExerciseFilterSheet(filter: $filter)
            }
            .sheet(isPresented: $showsNewExercise) {
                CustomExerciseEditor(exercise: nil)
            }
        }
        // Ponovni dodir na tab: novi stog bez otvorenih ekrana (Apple HIG).
        .id(rootReset)
    }

    /// Stog nakon preklapanja: popis iz lijevog stupca pa odabrana vježba (ako postoji).
    private var compactPath: NavigationPath {
        var path = NavigationPath()
        let summary = selection.flatMap { source in
            (catalogStore.summaries + customExercises.map(\.summary)).first { $0.source == source }
        }
        if route != .all || summary != nil { path.append(route) }
        if let summary { path.append(summary) }
        return path
    }
}

/// Lijevi stupac podijeljenog prikaza: odabir vrste, pretraga, filteri i popis vježbi.
/// Odabrana vježba ostaje označena, a otvara se u desnom stupcu.
private struct ExerciseSplitList: View {
    @Binding var route: ExerciseListRoute
    @Binding var selection: ExerciseSummary.Source?

    @Environment(CatalogStore.self) private var catalogStore
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var filter = ExerciseFilter()
    @State private var showsFilters = false
    @State private var showsNewExercise = false

    private static let routes: [ExerciseListRoute] = [.all] + ExerciseKind.allCases.map { .kind($0) } + [.custom]

    var body: some View {
        let results = catalogStore.search(filter, custom: customExercises)
        List(selection: $selection) {
            Group {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.routes, id: \.self) { item in
                                FilterChip(title: item.title, isSelected: route == item) { route = item }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                Section {
                    ForEach(results) { summary in
                        NavigationLink(value: summary.source) {
                            ExerciseRow(
                                summary: summary,
                                thumbnail: catalogStore.thumbnail(for: summary.source, customExercises: customExercises)
                            )
                        }
                        .openInWindowMenu(DetailWindow.exercise, value: summary.id)
                        .selectableRowBackground(selection == summary.source)
                    }
                }
            }
            .listRowBackground(AppPalette.card)
        }
        .appListBackground()
        .overlay { emptyState(results) }
        .navigationTitle("Vježbe")
        .searchable(text: $filter.query, prompt: "Pretraži vježbe")
        .toolbar {
            ExerciseListToolbar(
                isFiltered: filter.differs(from: route.initialFilter),
                showsFilters: $showsFilters, showsNewExercise: $showsNewExercise
            )
        }
        .sheet(isPresented: $showsFilters) {
            ExerciseFilterSheet(filter: $filter, base: route.initialFilter)
        }
        .sheet(isPresented: $showsNewExercise) {
            CustomExerciseEditor(exercise: nil)
        }
        // Druga vrsta počinje s njezinim filterom, a upit ostaje.
        .onChange(of: route, initial: true) { filter.reset(to: route.initialFilter) }
    }

    @ViewBuilder
    private func emptyState(_ results: [ExerciseSummary]) -> some View {
        if let errorText = catalogStore.errorText {
            ContentUnavailableView(
                "Katalog nije dostupan",
                systemImage: "exclamationmark.triangle",
                description: Text(errorText)
            )
        } else if results.isEmpty {
            if !filter.query.isEmpty {
                ContentUnavailableView.search(text: filter.query)
            } else if route == .custom && !filter.differs(from: route.initialFilter) {
                ContentUnavailableView(
                    "Nema vlastitih vježbi",
                    systemImage: "dumbbell",
                    description: Text("Vlastitu vježbu dodaj gumbom +.")
                )
            } else {
                ContentUnavailableView(
                    "Nema vježbi",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Nijedna vježba ne odgovara odabranim filterima.")
                )
            }
        }
    }
}

/// Gumbi Filteri i Nova vježba, isti na početnoj i na popisima.
private struct ExerciseListToolbar: ToolbarContent {
    let isFiltered: Bool
    @Binding var showsFilters: Bool
    @Binding var showsNewExercise: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Filteri", systemImage: isFiltered
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
}

/// Popis jedne vrste, svih ili vlastitih vježbi, s pretragom, filterima i brzim odabirom dijela tijela.
private struct ExerciseListScreen: View {
    let route: ExerciseListRoute

    @Environment(CatalogStore.self) private var catalogStore
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var filter: ExerciseFilter
    @State private var showsFilters = false
    @State private var showsNewExercise = false

    init(route: ExerciseListRoute) {
        self.route = route
        _filter = State(initialValue: route.initialFilter)
    }

    var body: some View {
        let results = catalogStore.search(filter, custom: customExercises)
        content(results)
            .navigationTitle(Text(route.title))
            .searchable(text: $filter.query, prompt: "Pretraži vježbe")
            .toolbar {
                ExerciseListToolbar(isFiltered: isFiltered, showsFilters: $showsFilters, showsNewExercise: $showsNewExercise)
            }
            .sheet(isPresented: $showsFilters) {
                ExerciseFilterSheet(filter: $filter, base: route.initialFilter)
            }
            .sheet(isPresented: $showsNewExercise) {
                CustomExerciseEditor(exercise: nil)
            }
    }

    @ViewBuilder
    private func content(_ results: [ExerciseSummary]) -> some View {
        if route == .custom && results.isEmpty && filter.query.isEmpty && !isFiltered {
            ContentUnavailableView(
                "Nema vlastitih vježbi",
                systemImage: "dumbbell",
                description: Text("Vlastitu vježbu dodaj gumbom +.")
            )
        } else {
            ExerciseResults(results: results, query: filter.query, customExercises: customExercises) {
                CategoryChips(categories: availableCategories, selection: $filter.categories)
            }
        }
    }

    /// Filteri iz lista uz početni filter popisa.
    private var isFiltered: Bool {
        filter.differs(from: route.initialFilter)
    }

    /// Dijelovi tijela koji postoje u ovom popisu (bez odabranog dijela tijela), redom kategorija.
    private var availableCategories: [ExerciseCategory] {
        var base = filter
        base.categories = []
        base.query = ""
        let present = Set(catalogStore.search(base, custom: customExercises).compactMap(\.category))
        return ExerciseCategory.allCases.filter(present.contains)
    }
}

/// Brzi odabir jednog dijela tijela iznad popisa. Skriven kad u popisu postoji samo jedan.
private struct CategoryChips: View {
    let categories: [ExerciseCategory]
    @Binding var selection: Set<ExerciseCategory>

    var body: some View {
        if categories.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "Sve", isSelected: selection.isEmpty) { selection = [] }
                    ForEach(categories, id: \.self) { category in
                        FilterChip(title: category.title, isSelected: selection == [category]) { selection = [category] }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
}

/// Gumb u obliku kapsule za brzi odabir iznad popisa (vrsta ili dio tijela).
private struct FilterChip: View {
    let title: LocalizedStringResource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) { Text(title) }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppPalette.onAccent)
                .buttonBorderShape(.capsule)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) { Text(title) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.primary)
        }
    }
}

/// Rezultati pretrage: popis u compact širini, mreža sa slikama u regular širini (iPad).
/// `header` stoji iznad prvog retka (brzi odabir dijela tijela).
private struct ExerciseResults<Header: View>: View {
    let results: [ExerciseSummary]
    let query: String
    let customExercises: [CustomExercise]
    @ViewBuilder var header: Header

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if let errorText = catalogStore.errorText {
            ContentUnavailableView(
                "Katalog nije dostupan",
                systemImage: "exclamationmark.triangle",
                description: Text(errorText)
            )
        } else if results.isEmpty {
            VStack(spacing: 0) {
                header
                if query.isEmpty {
                    ContentUnavailableView(
                        "Nema vježbi",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Nijedna vježba ne odgovara odabranim filterima.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        } else if sizeClass == .regular {
            grid
        } else {
            List {
                Group {
                    if Header.self != EmptyView.self {
                        Section {
                            header
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(results) { summary in
                            NavigationLink(value: summary) {
                                ExerciseRow(summary: summary, thumbnail: thumbnail(for: summary))
                            }
                            .openInWindowMenu(DetailWindow.exercise, value: summary.id)
                        }
                    }
                }
                .listRowBackground(AppPalette.card)
            }
            .appListBackground()
        }
    }

    private var grid: some View {
        ScrollView {
            header
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
        .background(AppPalette.background)
    }

    private func thumbnail(for summary: ExerciseSummary) -> ExerciseThumbnail.Source? {
        catalogStore.thumbnail(for: summary.source, customExercises: customExercises)
    }
}

extension ExerciseResults where Header == EmptyView {
    init(results: [ExerciseSummary], query: String, customExercises: [CustomExercise]) {
        self.init(results: results, query: query, customExercises: customExercises) { EmptyView() }
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
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: CornerRadius.card))
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: CornerRadius.card))
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
    let thumbnail: ExerciseThumbnail.Source?

    var body: some View {
        HStack(spacing: 12) {
            ExerciseRowThumbnail(source: thumbnail)
            texts
        }
    }

    private var texts: some View {
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
