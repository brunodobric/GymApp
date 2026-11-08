import Catalog
import Models
import PhotosUI
import SwiftData
import SwiftUI

/// Izrada i uređivanje vlastite vježbe. Za novu vježbu `exercise` je nil.
struct CustomExerciseEditor: View {
    let exercise: CustomExercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var details = ""
    @State private var kind = ExerciseKind.strength
    @State private var category: ExerciseCategory?
    @State private var equipment: Equipment?
    @State private var inputType = ExerciseInputType.weightReps
    @State private var muscles: Set<Muscle> = []
    @State private var imageData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var errorText: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naziv", text: $name)
                    TextField("Opis (neobavezno)", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Picker("Vrsta vježbe", selection: $kind) {
                        ForEach(ExerciseKind.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    Picker("Kategorija", selection: $category) {
                        Text("Nije odabrano").tag(ExerciseCategory?.none)
                        ForEach(ExerciseCategory.allCases, id: \.self) { value in
                            Text(value.title).tag(ExerciseCategory?.some(value))
                        }
                    }
                    Picker("Oprema", selection: $equipment) {
                        Text("Nije odabrano").tag(Equipment?.none)
                        ForEach(Equipment.allCases, id: \.self) { value in
                            Text(value.title).tag(Equipment?.some(value))
                        }
                    }
                    Picker("Unos", selection: $inputType) {
                        ForEach(ExerciseInputType.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                } footer: {
                    Text("Vrsta unosa određuje polja u retku serije i način računanja volumena.")
                }

                Section("Mišići") {
                    ForEach(Muscle.allCases, id: \.self) { muscle in
                        SelectionRow(title: muscle.title, value: muscle, selection: $muscles)
                    }
                }

                Section("Slika") {
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .accessibilityHidden(true)
                        Button("Ukloni sliku", role: .destructive) {
                            self.imageData = nil
                            photoItem = nil
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(imageData == nil ? "Odaberi sliku" : "Zamijeni sliku")
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle(exercise == nil ? "Nova vježba" : "Uredi vježbu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Odustani") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spremi", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            // Kardio kategorija je uvijek kardio vrsta (kao u katalogu).
            .onChange(of: category) { old, new in
                if new == .cardio {
                    kind = .cardio
                } else if old == .cardio && kind == .cardio {
                    kind = .strength
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
        }
    }

    private func load() {
        guard let exercise else { return }
        name = exercise.name
        details = exercise.details
        kind = exercise.kind
        category = exercise.category
        equipment = exercise.equipment
        inputType = exercise.inputType
        muscles = Set(exercise.muscles)
        imageData = exercise.imageData
    }

    /// Slika se smanjuje na najviše 1200 px, da baza i iCloud ne nose izvornu fotografiju.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            imageData = Self.downscaledJPEG(image, maxDimension: 1200)
        } catch {
            errorText = String(localized: "Slika se nije mogla učitati.")
        }
    }

    private static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private func save() {
        let target = exercise ?? CustomExercise(name: "")
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.details = details
        target.category = category
        target.kind = kind
        target.equipment = equipment
        target.inputType = inputType
        // Redoslijed mišića je stabilan (kao u katalogu), ne ovisi o redoslijedu odabira.
        target.muscles = Muscle.allCases.filter { muscles.contains($0) }
        target.imageData = imageData
        if exercise == nil { context.insert(target) }
        do {
            try context.save()
            dismiss()
        } catch {
            errorText = String(localized: "Vježba se nije mogla spremiti.")
        }
    }
}
