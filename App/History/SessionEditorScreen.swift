import Catalog
import Models
import SwiftData
import SwiftUI
import Training
import Units

/// Kopija odrađenog treninga u zasebnom kontekstu bez automatskog spremanja: uređivač mijenja nju,
/// a odustajanje samo odbacuje kontekst.
struct SessionEditDraft: Identifiable {
    let id = UUID()
    let context: ModelContext
    let session: Session

    /// nil kad trening nije spremljen u bazu (npr. trening iz Zdravlja prikazan bez lokalne kopije).
    init?(of session: Session, in container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let copy = context.model(for: session.persistentModelID) as? Session else { return nil }
        self.context = context
        self.session = copy
    }
}

/// Uređivanje odrađenog treninga: naziv, početak i kraj, vježbe, serije i bilješke.
/// Izmjene se spremaju tek na "Spremi", a "Odustani" ih odbacuje.
struct SessionEditorScreen: View {
    @Bindable var session: Session
    let editor: SessionEditor

    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]
    @State private var showsPicker = false
    @State private var confirmsDiscard = false
    @State private var hasChanges = false
    @State private var errorText: String?

    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }
    private var unit: WeightUnit { settings?.weightUnit ?? .kilograms }
    private var exercises: [SessionExercise] { session.orderedExercises.filter { !$0.isRemoved && !$0.isDeleted } }

    var body: some View {
        NavigationStack {
            List {
                Section("Naziv") {
                    TextField("Naziv treninga", text: $session.name)
                }
                Section {
                    DatePicker("Početak", selection: $session.startedAt)
                    if session.endedAt != nil {
                        DatePicker("Kraj", selection: endBinding, in: session.startedAt...)
                    }
                } footer: {
                    if session.healthKitWorkoutId != nil {
                        Text("Izmjene se ne prenose u Zdravlje.")
                    }
                }
                ForEach(exercises) { exercise in
                    Section {
                        exerciseRows(exercise)
                    } header: {
                        exerciseHeader(exercise)
                    }
                }
                Section {
                    Button("Dodaj vježbu", systemImage: "plus") { showsPicker = true }
                } footer: {
                    Text("Serije bez kvačice i vježbe bez završene serije neće se spremiti.")
                }
                Section("Bilješke") {
                    TextField("Bilješke", text: $session.notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("Uredi trening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Odustani") {
                        if hasChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spremi") { save() }
                        .disabled(session.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .onChange(of: session.name) { hasChanges = true }
            .onChange(of: session.startedAt) { hasChanges = true }
            .onChange(of: session.endedAt) { hasChanges = true }
            .onChange(of: session.notes) { hasChanges = true }
            .sheet(isPresented: $showsPicker) {
                ExercisePickerSheet(title: "Dodaj vježbu") { summary, inputType in
                    editor.addExercise(summary.ref, inputType: inputType, to: session)
                    hasChanges = true
                }
            }
            .confirmationDialog("Odbaciti izmjene?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Odbaci izmjene", role: .destructive) { dismiss() }
                Button("Nastavi uređivati", role: .cancel) {}
            }
            .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("U redu") {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    /// Kraj se ne može postaviti prije početka.
    private var endBinding: Binding<Date> {
        Binding(
            get: { max(session.endedAt ?? session.startedAt, session.startedAt) },
            set: { session.endedAt = $0 }
        )
    }

    private func exerciseHeader(_ exercise: SessionExercise) -> some View {
        HStack {
            Text(exercise.exerciseName)
            Spacer()
            Button("Obriši vježbu", systemImage: "trash", role: .destructive) {
                withAnimation { editor.removeExercise(exercise) }
                hasChanges = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func exerciseRows(_ exercise: SessionExercise) -> some View {
        let sets = exercise.orderedSets.filter { !$0.isDeleted }
        ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
            SetRow(
                set: set, inputType: exercise.inputType, position: position(of: index, in: sets),
                previousText: nil, suggestion: nil, isHighlighted: false, unit: unit,
                effortScale: settings?.effortScale ?? .rpe, dimsCompleted: false,
                onEdit: { hasChanges = true },
                onToggleComplete: { toggle(set) },
                onChangeKind: { kind in
                    set.kind = kind
                    hasChanges = true
                },
                onDelete: { delete(set) }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Obriši", systemImage: "trash", role: .destructive) { delete(set) }
                    .tint(.red)
            }
        }
        HStack {
            Button("Dodaj seriju", systemImage: "plus") { add(.working, to: exercise) }
            Spacer()
            Button("Zagrijavanje", systemImage: "flame") { add(.warmUp, to: exercise) }
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }

    /// Redni broj za oznaku serije, zasebno za radne serije i zagrijavanje (kao u aktivnom treningu).
    private func position(of index: Int, in sets: [SetLog]) -> Int {
        let kind = sets[index].kind
        return sets[...index].filter { $0.kind == kind }.count
    }

    private func add(_ kind: SetKind, to exercise: SessionExercise) {
        editor.addSet(to: exercise, kind: kind)
        hasChanges = true
    }

    private func delete(_ set: SetLog) {
        withAnimation { editor.removeSet(set) }
        hasChanges = true
    }

    private func toggle(_ set: SetLog) {
        do {
            try editor.toggleCompleted(set)
            hasChanges = true
        } catch {
            errorText = String(localized: "Upiši sve vrijednosti serije prije označavanja.")
        }
    }

    private func save() {
        do {
            try editor.save(session)
            dismiss()
        } catch WorkoutError.nothingCompleted {
            errorText = String(localized: "Trening bez ijedne završene serije ne može se spremiti. Ako ga više ne trebaš, obriši ga.")
        } catch {
            errorText = String(localized: "Trening se nije mogao spremiti.")
        }
    }
}
