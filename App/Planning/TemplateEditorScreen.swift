import Catalog
import Models
import Planning
import SwiftData
import SwiftUI
import Units

/// Uređivač treninga (predloška): vježbe, redoslijed, supersetovi, ciljane serije i pauze.
///
/// Vježbe se dodaju iz kataloga u bočnoj ploči (inspector), koja se otvara gumbom Dodaj vježbe: na iPadu
/// stoji uz popis, pa se vježbe mogu odabrati više odjednom ili povući na željeno mjesto u popisu. Na iPhoneu
/// se ploča otvara kao list.
///
/// U kartici Rasporedi trening se otvara samo za prikaz, a uređuje se nakon gumba Uredi (`PlanningEditing`).
struct TemplateEditorScreen: View {
    @Bindable var template: WorkoutTemplate
    /// Prikaz ili uređivanje. Bez toga trening se uvijek uređuje.
    var editing: PlanningEditing?

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]
    @State private var showsCatalog = false
    @State private var errorText: String?

    private var engine: TemplateEngine { TemplateEngine(context: context) }
    private var isEditing: Bool { editing?.isEditing ?? true }

    var body: some View {
        List {
            Section("Naziv") {
                TextField("Naziv treninga", text: $template.name)
                    .disabled(!isEditing)
            }
            Section("Vježbe") {
                ForEach(template.orderedExercises) { exercise in
                    NavigationLink(value: exercise) { row(for: exercise) }
                        // Superset povlačenjem udesno, izvan uređivanja (u njemu povlačenje ne radi).
                        .swipeActions(edge: .leading) { supersetAction(for: exercise) }
                }
                // Premještanje i brisanje samo u uređivanju (crtice i znak za brisanje).
                .onMove(perform: isEditing ? moveExercises : nil)
                .onDelete(perform: isEditing ? deleteExercises : nil)
                // Vježba povučena iz kataloga umeće se na mjesto gdje je puštena.
                .dropDestination(for: String.self) { payloads, index in
                    guard isEditing else { return }
                    add(catalogStore.choices(from: payloads, custom: customExercises), at: index)
                }
                if isEditing {
                    Button("Dodaj vježbe", systemImage: "plus") { showsCatalog = true }
                        // Puštena na gumb (i u praznom treningu) vježba ide na kraj.
                        .dropDestination(for: String.self) { payloads, _ in
                            let choices = catalogStore.choices(from: payloads, custom: customExercises)
                            add(choices, at: nil)
                            return !choices.isEmpty
                        }
                } else if template.orderedExercises.isEmpty {
                    Text("Još nema vježbi u treningu.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .planningEditMode(editing)
        .navigationTitle(template.name.isEmpty ? String(localized: "Trening") : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .planningEditToolbar(editing)
        // Katalog se otvara samo gumbom Dodaj vježbe (i ⌘K), a zatvara gumbom Zatvori u ploči.
        .commandShortcut("Dodaj vježbe", key: "k") { if isEditing { showsCatalog = true } }
        .onChange(of: isEditing) { _, isEditing in if !isEditing { showsCatalog = false } }
        .navigationDestination(for: TemplateExercise.self) { TemplateExerciseEditor(exercise: $0) }
        .planningPanel(isPresented: $showsCatalog, minWidth: 300, idealWidth: 360, maxWidth: 480) {
            ExerciseCatalogPanel(isPresented: $showsCatalog) { add($0, at: nil) }
        }
        .errorAlert($errorText)
        .onDisappear { try? context.save() }
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        try? engine.moveExercises(in: template, from: source, to: destination)
    }

    private func deleteExercises(at offsets: IndexSet) {
        let list = template.orderedExercises
        for index in offsets { try? engine.removeExercise(list[index]) }
    }

    private func add(_ choices: [ExerciseChoice], at index: Int?) {
        guard !choices.isEmpty else { return }
        do {
            try engine.addExercises(choices, to: template, at: index)
        } catch {
            errorText = String(localized: "Vježba se nije mogla dodati.")
        }
    }

    private func row(for exercise: TemplateExercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.exerciseName)
            HStack(spacing: 6) {
                if exercise.supersetGroupId != nil {
                    Label("Superset", systemImage: "link")
                }
                Text(setSummary(exercise))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    /// Npr. "3 serije × 8".
    private func setSummary(_ exercise: TemplateExercise) -> String {
        let sets = exercise.orderedSets.filter { $0.kind == .working }
        let reps = sets.first?.targetReps
        let count = sets.count
        if let reps, let max = sets.first?.targetRepsMax, max > reps {
            return String(localized: "\(count) serije × \(reps)–\(max)")
        }
        if let reps { return String(localized: "\(count) serije × \(reps)") }
        return String(localized: "\(count) serije")
    }

    /// Spoji vježbu sa sljedećom u superset, ili je izdvoji iz njega.
    @ViewBuilder
    private func supersetAction(for exercise: TemplateExercise) -> some View {
        if exercise.supersetGroupId != nil {
            Button("Izdvoji", systemImage: "link.badge.minus") {
                try? engine.removeFromSuperset(exercise)
            }
            .tint(.orange)
        } else if let next = nextExercise(after: exercise), next.supersetGroupId == nil {
            Button("Superset", systemImage: "link") {
                try? engine.makeSuperset([exercise, next], in: template)
            }
            .tint(.indigo)
        }
    }

    private func nextExercise(after exercise: TemplateExercise) -> TemplateExercise? {
        let list = template.orderedExercises
        guard let index = list.firstIndex(where: { $0.id == exercise.id }), index + 1 < list.count else { return nil }
        return list[index + 1]
    }
}

/// Serije jedne vježbe u treningu: broj i vrsta serija, ciljana težina i ponavljanja, pauza.
struct TemplateExerciseEditor: View {
    @Bindable var exercise: TemplateExercise

    @Environment(\.modelContext) private var context
    // Jedinica iz upita, dostupna već pri prvom prikazu: redak serije zapamti tekst težine u jedinici
    // koju je dobio prvi put, pa bi kasnije stigla jedinica (npr. iz `.task`) krivo preračunala unos.
    @Query private var settingsList: [UserSettings]
    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }

    private var engine: TemplateEngine { TemplateEngine(context: context) }

    var body: some View {
        List {
            Section("Serije") {
                ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.id) { index, set in
                    TemplateSetRow(set: set, inputType: exercise.inputType, unit: unit, position: index + 1)
                        // Promjena jedinice gradi redak iznova, da tekst težine bude u novoj jedinici.
                        // Id sadrži i seriju: samo `unit` bi svim retcima dao isti identitet u listi.
                        .id("\(set.id.uuidString)-\(unit.rawValue)")
                }
                .onDelete(perform: deleteSets)
                Button("Dodaj radnu seriju", systemImage: "plus") { _ = try? engine.addSet(to: exercise) }
                Button("Dodaj zagrijavanje", systemImage: "flame") { _ = try? engine.addSet(to: exercise, kind: .warmUp) }
            }
            Group {
                Section("Pauza") {
                    Toggle("Vlastita pauza", isOn: Binding(
                        get: { exercise.restSeconds != nil },
                        set: { try? engine.setRest($0 ? 90 : nil, for: exercise) }
                    ))
                    if let rest = exercise.restSeconds {
                        Stepper(value: Binding(
                            get: { rest },
                            set: { try? engine.setRest($0, for: exercise) }
                        ), in: 0...600, step: 15) {
                            Text("\(rest) s")
                        }
                    }
                }
                Section("Bilješka") {
                    TextField("Bilješka uz vježbu", text: $exercise.notes, axis: .vertical)
                }
            }
        }
        .navigationTitle(exercise.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
    }

    private func deleteSets(at offsets: IndexSet) {
        let list = exercise.orderedSets
        for index in offsets { try? engine.removeSet(list[index]) }
    }
}

private struct TemplateSetRow: View {
    let set: TemplateSet
    let inputType: ExerciseInputType
    let unit: WeightUnit
    let position: Int

    @State private var weight: String
    @State private var reps: String

    init(set: TemplateSet, inputType: ExerciseInputType, unit: WeightUnit, position: Int) {
        self.set = set
        self.inputType = inputType
        self.unit = unit
        self.position = position
        _weight = State(initialValue: NumberInput.format(set.targetWeightKg.map {
            WeightConversion.displayValue(fromKilograms: $0, in: unit)
        }))
        _reps = State(initialValue: set.targetReps.map(String.init) ?? "")
    }

    private var usesWeight: Bool {
        inputType == .weightReps || inputType == .weightedBodyweight || inputType == .assisted
    }

    private var usesReps: Bool {
        usesWeight || inputType == .bodyweight
    }

    var body: some View {
        HStack(spacing: 10) {
            SetBadge(kind: set.kind, number: position)
            if usesWeight {
                WheelInputField.weight(
                    weightTitle, hint: weightHint, text: $weight, unit: unit,
                    fallback: WheelOptions.defaultWeight(for: unit, isExtraLoad: inputType != .weightReps)
                )
            }
            if usesReps {
                WheelInputField.reps("Ponavljanja", hint: "×", text: $reps, fallback: WheelOptions.defaultReps)
            }
            if !usesReps {
                Text("Bez ciljeva").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .onChange(of: weight) { _, _ in apply() }
        .onChange(of: reps) { _, _ in apply() }
    }

    private var weightTitle: LocalizedStringKey {
        switch inputType {
        case .weightedBodyweight: "Dodatna težina"
        case .assisted: "Pomoć"
        default: "Težina"
        }
    }

    private var weightHint: String {
        switch inputType {
        case .weightedBodyweight: "+\(unit.symbol)"
        case .assisted: "−\(unit.symbol)"
        default: unit.symbol
        }
    }

    private func apply() {
        set.targetWeightKg = NumberInput.parse(weight).map { WeightConversion.kilograms(from: $0, in: unit) }
        set.targetReps = Int(reps.trimmingCharacters(in: .whitespaces))
        // Ručno upisan cilj iznad gornje granice raspona poništava raspon.
        if let max = set.targetRepsMax, max <= set.targetReps ?? .max { set.targetRepsMax = nil }
    }
}
