import Catalog
import Models
import Stats
import SwiftData
import SwiftUI

/// Pronalazi vježbu za odabrani redak: službenu u katalogu ili vlastitu u bazi.
///
/// Iz aktivnog treninga se otvara samo za čitanje (`allowsRemoving: false`): vlastita vježba se tamo
/// može urediti (npr. dopisati opis), ali ne i ukloniti.
struct ExerciseDetailScreen: View {
    let source: ExerciseSummary.Source
    var allowsRemoving = true

    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]

    init(summary: ExerciseSummary) {
        self.source = summary.source
    }

    init(source: ExerciseSummary.Source, allowsRemoving: Bool = true) {
        self.source = source
        self.allowsRemoving = allowsRemoving
    }

    var body: some View {
        switch source {
        case .catalog(let id):
            if let exercise = catalogStore.catalog?.exercise(withID: id) {
                CatalogExerciseDetail(exercise: exercise, linksToSessions: allowsRemoving)
            } else {
                missing
            }
        case .custom(let id):
            if let exercise = customExercises.first(where: { $0.id == id }) {
                CustomExerciseDetail(exercise: exercise, allowsRemoving: allowsRemoving)
            } else {
                missing
            }
        }
    }

    private var missing: some View {
        ContentUnavailableView("Vježba nije pronađena", systemImage: "questionmark.circle")
    }
}

private struct CatalogExerciseDetail: View {
    let exercise: CatalogExercise
    /// Iz aktivnog treninga retci povijesti ne vode na stare treninge.
    let linksToSessions: Bool
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var context
    @State private var history: ExerciseHistory?

    private var ref: ExerciseRef {
        ExerciseRef(catalogId: exercise.id, name: exercise.displayName(language: catalogStore.language))
    }

    var body: some View {
        let language = catalogStore.language
        let name = exercise.displayName(language: language)
        let steps = exercise.displayInstructions(language: language)
        let mistakes = exercise.displayCommonMistakes(language: language)

        List {
            switch catalogStore.illustration(for: exercise) {
            case let .video(path, poster):
                if let video = catalogStore.mediaURL(path) {
                    Section {
                        ExerciseVideoView(
                            video: video,
                            poster: poster.flatMap { catalogStore.mediaURL($0) },
                            accessibilityText: name
                        )
                        .listRowInsets(EdgeInsets())
                    }
                }
            case let .poster(path):
                if let url = catalogStore.mediaURL(path), let image = UIImage(contentsOfFile: url.path) {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(name)
                            .listRowInsets(EdgeInsets())
                    }
                }
            case .unavailable:
                EmptyView()
            }

            Section("Mišići") {
                LabeledContent("Primarni") { Text(exercise.primaryMuscles.formattedList) }
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Sekundarni") { Text(exercise.secondaryMuscles.formattedList) }
                }
            }

            Section("Detalji") {
                LabeledContent("Kategorija") { Text(exercise.category.title) }
                LabeledContent("Oprema") { Text(exercise.equipment.title) }
                LabeledContent("Razina") { Text(exercise.level.title) }
                if let mechanic = exercise.mechanic {
                    LabeledContent("Vrsta") { Text(mechanic.title) }
                }
                LabeledContent("Unos") { Text(exercise.inputType.title) }
                if exercise.inputType.hasWeight {
                    ExerciseWeightStepRow(exercise: ref, equipment: exercise.equipment)
                }
            }

            Section {
                if steps.isEmpty {
                    Text("Upute za ovu vježbu nisu dostupne.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
            } header: {
                Text("Upute")
            } footer: {
                if !steps.isEmpty && exercise.instructions[language] == nil && language != "en" {
                    Text("Upute za ovu vježbu su zasad samo na engleskom.")
                }
            }

            if !mistakes.isEmpty {
                Section("Česte greške") {
                    ForEach(Array(mistakes.enumerated()), id: \.offset) { _, mistake in
                        Text(mistake)
                    }
                }
            }

            if let history {
                ExerciseHistorySection(ref: ref, history: history, linksToSessions: linksToSessions)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { history = ExerciseHistoryLoader.load(ref, context: context) }
    }
}

private struct CustomExerciseDetail: View {
    let exercise: CustomExercise
    let allowsRemoving: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showsEditor = false
    @State private var showsRemoveConfirmation = false
    @State private var errorText: String?
    @State private var history: ExerciseHistory?

    var body: some View {
        List {
            if let data = exercise.imageData, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(exercise.name)
                        .listRowInsets(EdgeInsets())
                }
            }

            if exercise.isArchived {
                Section {
                    Label("Arhivirana je i skrivena iz odabira.", systemImage: "archivebox")
                    Button("Vrati vježbu") {
                        exercise.isArchived = false
                        try? context.save()
                    }
                }
            }

            if !exercise.details.isEmpty {
                Section("Opis") { Text(exercise.details) }
            } else if exercise.imageData == nil {
                // Vlastita vježba bez slike i opisa: stranica ne ostaje prazna, nego kaže kako je dopuniti.
                Section {
                    Button("Dodaj opis i sliku", systemImage: "square.and.pencil") { showsEditor = true }
                } footer: {
                    Text("Ovo je tvoja vježba, pa nema animaciju iz kataloga.")
                }
            }

            Section("Detalji") {
                if let category = exercise.category {
                    LabeledContent("Kategorija") { Text(category.title) }
                }
                if let equipment = exercise.equipment {
                    LabeledContent("Oprema") { Text(equipment.title) }
                }
                if !exercise.muscles.isEmpty {
                    LabeledContent("Mišići") { Text(exercise.muscles.formattedList) }
                }
                LabeledContent("Unos") { Text(exercise.inputType.title) }
                if exercise.inputType.hasWeight {
                    ExerciseWeightStepRow(exercise: exercise.ref, equipment: exercise.equipment)
                }
            }

            if let history {
                // Iz aktivnog treninga (bez uklanjanja) retci ne vode na stare treninge.
                ExerciseHistorySection(ref: exercise.summary.ref, history: history, linksToSessions: allowsRemoving)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { history = ExerciseHistoryLoader.load(exercise.summary.ref, context: context) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if allowsRemoving {
                    Menu("Više", systemImage: "ellipsis.circle") {
                        Button("Uredi", systemImage: "pencil") { showsEditor = true }
                        Button("Ukloni", systemImage: "trash", role: .destructive) {
                            showsRemoveConfirmation = true
                        }
                    }
                } else {
                    Button("Uredi") { showsEditor = true }
                }
            }
        }
        .sheet(isPresented: $showsEditor) {
            CustomExerciseEditor(exercise: exercise)
        }
        .confirmationDialog("Ukloniti vježbu?", isPresented: $showsRemoveConfirmation, titleVisibility: .visible) {
            Button("Ukloni", role: .destructive, action: remove)
        } message: {
            Text("Ako je vježba već korištena u treningu, samo će se arhivirati i povijest ostaje.")
        }
        .errorAlert($errorText)
    }

    private func remove() {
        do {
            let result = try CustomExerciseStore.remove(exercise, in: context)
            if result == .deleted { dismiss() }
        } catch {
            errorText = String(localized: "Vježba se nije mogla ukloniti.")
        }
    }
}
