import Catalog
import Models
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
                CatalogExerciseDetail(exercise: exercise)
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
    @Environment(CatalogStore.self) private var catalogStore

    var body: some View {
        let language = catalogStore.language
        let name = exercise.displayName(language: language)
        let steps = exercise.displayInstructions(language: language)

        List {
            switch exercise.illustration {
            case let .animation(start, end):
                Section {
                    ExercisePhotoAnimationView(
                        start: catalogStore.imageURL(start),
                        end: catalogStore.imageURL(end),
                        accessibilityText: name
                    )
                    .listRowInsets(EdgeInsets())
                }
            case let .photo(path):
                Section {
                    if let image = UIImage(contentsOfFile: catalogStore.imageURL(path).path) {
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
            }

            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
            } header: {
                Text("Upute")
            } footer: {
                if exercise.instructions[language] == nil && language != "en" {
                    Text("Upute za ovu vježbu su zasad samo na engleskom.")
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
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
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
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
