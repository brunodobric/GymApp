import Catalog
import Models
import Planning
import SwiftData
import SwiftUI
import Units

/// Uređivač treninga (predloška): vježbe, redoslijed, supersetovi, ciljane serije i pauze.
///
/// Vježbe se dodaju iz kataloga u bočnoj ploči (inspector): na iPadu stoji uz popis, pa se vježbe mogu
/// odabrati više odjednom ili povući na željeno mjesto u popisu. Na iPhoneu se ploča otvara kao list.
struct TemplateEditorScreen: View {
    @Bindable var template: WorkoutTemplate

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]
    @State private var showsCatalog = false
    @State private var errorText: String?

    private var engine: TemplateEngine { TemplateEngine(context: context) }

    var body: some View {
        List {
            Section("Naziv") {
                TextField("Naziv treninga", text: $template.name)
            }
            Section("Vježbe") {
                ForEach(template.orderedExercises) { exercise in
                    NavigationLink(value: exercise) { row(for: exercise) }
                        .swipeActions(edge: .leading) { supersetAction(for: exercise) }
                }
                .onMove { source, destination in
                    try? engine.moveExercises(in: template, from: source, to: destination)
                }
                .onDelete { offsets in
                    let list = template.orderedExercises
                    for index in offsets { try? engine.removeExercise(list[index]) }
                }
                // Vježba povučena iz kataloga umeće se na mjesto gdje je puštena.
                .dropDestination(for: String.self) { payloads, index in
                    add(catalogStore.choices(from: payloads, custom: customExercises), at: index)
                }
                Button("Dodaj vježbe", systemImage: "plus") { showsCatalog = true }
                    // Puštena na gumb (i u praznom treningu) vježba ide na kraj.
                    .dropDestination(for: String.self) { payloads, _ in
                        let choices = catalogStore.choices(from: payloads, custom: customExercises)
                        add(choices, at: nil)
                        return !choices.isEmpty
                    }
            }
        }
        .navigationTitle(template.name.isEmpty ? String(localized: "Trening") : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Katalog", systemImage: "sidebar.trailing") { showsCatalog.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
        .navigationDestination(for: TemplateExercise.self) { TemplateExerciseEditor(exercise: $0) }
        .inspector(isPresented: $showsCatalog) {
            ExerciseCatalogPanel(isPresented: $showsCatalog) { add($0, at: nil) }
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("U redu") {}
        } message: {
            Text(errorText ?? "")
        }
        .onDisappear { try? context.save() }
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
    @State private var unit: WeightUnit = .kilograms

    private var engine: TemplateEngine { TemplateEngine(context: context) }

    var body: some View {
        List {
            Section("Serije") {
                ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.id) { index, set in
                    TemplateSetRow(set: set, inputType: exercise.inputType, unit: unit, position: index + 1)
                }
                .onDelete { offsets in
                    let list = exercise.orderedSets
                    for index in offsets { try? engine.removeSet(list[index]) }
                }
                Button("Dodaj radnu seriju", systemImage: "plus") { _ = try? engine.addSet(to: exercise) }
                Button("Dodaj zagrijavanje", systemImage: "flame") { _ = try? engine.addSet(to: exercise, kind: .warmUp) }
            }
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
        .navigationTitle(exercise.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .task { unit = (try? GymQueries(context: context).settings())?.weightUnit ?? .kilograms }
        .onDisappear { try? context.save() }
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
            Text(set.kind == .warmUp ? "Z" : "\(position)")
                .font(.subheadline.bold())
                .frame(width: 30, height: 30)
                .background(set.kind == .warmUp ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.15), in: .circle)
            if usesWeight {
                field("Težina", unit.symbol, $weight)
            }
            if usesReps {
                field("Ponavljanja", "×", $reps)
            }
            if !usesReps {
                Text("Bez ciljeva").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .onChange(of: weight) { _, _ in apply() }
        .onChange(of: reps) { _, _ in apply() }
    }

    private func field(_ title: LocalizedStringKey, _ hint: String, _ text: Binding<String>) -> some View {
        TextField(hint, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .frame(minWidth: 52, maxWidth: 80)
            .padding(.vertical, 8)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .accessibilityLabel(Text(title))
    }

    private func apply() {
        set.targetWeightKg = NumberInput.parse(weight).map { WeightConversion.kilograms(from: $0, in: unit) }
        set.targetReps = Int(reps.trimmingCharacters(in: .whitespaces))
    }
}
