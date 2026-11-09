import Connectivity
import Models
import SwiftUI
import Training
import Units

/// Aktivni trening na satu: lijevo kontrole (trajanje, puls, završetak), u sredini serija ili odmor,
/// desno popis vježbi i serija.
struct WatchWorkoutView: View {
    enum Page: Hashable {
        case controls, set, list
    }

    @Environment(WatchWorkoutStore.self) private var store
    @State private var page: Page = .set

    var body: some View {
        TabView(selection: $page) {
            WatchControlsView().tag(Page.controls)
            Group {
                if store.isResting, let timer = store.restTimer {
                    WatchRestView(timer: timer)
                } else {
                    WatchSetView()
                }
            }
            .tag(Page.set)
            WatchExerciseListView { page = .set }.tag(Page.list)
        }
        .tabViewStyle(.page)
        .alert("Greška", isPresented: Binding(get: { store.errorText != nil }, set: { if !$0 { store.errorText = nil } })) {
            Button("U redu") {}
        } message: {
            Text(store.errorText ?? "")
        }
    }
}

// MARK: - Serija

/// Trenutna vježba i serija s velikim gumbom za kvačicu. Težina i ponavljanja mijenjaju se Digital Crownom:
/// dodir na vrijednost bira koju kruna mijenja.
struct WatchSetView: View {
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        if let current = store.currentSet {
            content(exercise: current.exercise, set: current.set)
        } else {
            exerciseDone
        }
    }

    private func content(exercise: ExerciseSnapshot, set: SetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.exercise.name)
                .font(.itemTitle)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(setLabel(exercise: exercise, set: set))
                .font(.footnote)
                .foregroundStyle(set.kind == .warmUp ? .orange : .secondary)
            Spacer(minLength: 0)
            WatchSetValuesEditor(exercise: exercise, set: set)
            Spacer(minLength: 0)
            HStack {
                Button("Prethodna vježba", systemImage: "chevron.backward") { store.moveExercise(by: -1) }
                    .disabled(!store.canMoveExercise(by: -1))
                Button("Završi seriju", systemImage: "checkmark") { store.completeCurrentSet() }
                    .buttonStyle(.borderedProminent)
                    // Zelena znači gotovu seriju (kao kvačica na iPhoneu), pa ne prati akcent.
                    .tint(.green)
                Button("Sljedeća vježba", systemImage: "chevron.forward") { store.moveExercise(by: 1) }
                    .disabled(!store.canMoveExercise(by: 1))
            }
            .labelStyle(.iconOnly)
            .font(.title3)
        }
        .scenePadding(.horizontal)
    }

    private func setLabel(exercise: ExerciseSnapshot, set: SetSnapshot) -> String {
        let ordered = exercise.orderedSets
        let number = (ordered.firstIndex { $0.id == set.id } ?? 0) + 1
        let base = String(localized: "Serija \(number) od \(ordered.count)")
        return set.kind == .warmUp ? base + " · " + String(localized: "zagrijavanje") : base
    }

    /// Vježba nema nezavršenih serija: dodaj seriju, idi dalje ili završi trening.
    private var exerciseDone: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let exercise = store.currentExercise {
                    Text(exercise.exercise.name).font(.itemTitle).multilineTextAlignment(.center)
                }
                Text(store.showsFinishPrompt ? "Sve serije su gotove" : "Vježba je gotova")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if store.showsFinishPrompt {
                    Button("Završi trening", systemImage: "flag.checkered") { store.finish() }
                        .buttonStyle(.borderedProminent)
                }
                if let exercise = store.currentExercise {
                    Button("Dodaj seriju", systemImage: "plus") { store.addSet(to: exercise.id) }
                }
                if store.canMoveExercise(by: 1) {
                    Button("Sljedeća vježba", systemImage: "chevron.forward") { store.moveExercise(by: 1) }
                }
            }
        }
    }
}

/// Vrijednosti serije. Odabrana vrijednost je obrubljena, a kruna je mijenja u koracima polja.
struct WatchSetValuesEditor: View {
    let exercise: ExerciseSnapshot
    let set: SetSnapshot

    @Environment(WatchWorkoutStore.self) private var store
    @FocusState private var focused: WatchSetField?
    @State private var values: [WatchSetField: Double] = [:]

    private var fields: [WatchSetField] { WatchSetField.fields(for: exercise.inputType) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                if index > 0 {
                    Text(fields == [.duration, .distance] ? "·" : "×")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                fieldView(field)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: load)
        .onChange(of: set) { load() }
    }

    private func fieldView(_ field: WatchSetField) -> some View {
        let binding = Binding<Double>(
            get: { values[field] ?? field.value(in: set, unit: store.unit) },
            set: { newValue in
                values[field] = newValue
                store.setValue(newValue, field: field, setID: set.id)
            }
        )
        let range = field.range(unit: store.unit)
        return VStack(spacing: 0) {
            Text(field.text(in: set, unit: store.unit))
                .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(field.unitLabel(unit: store.unit))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused == field ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: focused == field ? 2 : 1)
        }
        .focusable()
        .focused($focused, equals: field)
        .digitalCrownRotation(
            binding, from: range.lowerBound, through: range.upperBound, by: field.step(unit: store.unit),
            sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Okreni Digital Crown za promjenu"))
    }

    /// Vrijednosti nove serije (ili promijenjene na iPhoneu). Kruna odmah mijenja prvo polje.
    private func load() {
        values = Dictionary(uniqueKeysWithValues: fields.map { ($0, $0.value(in: set, unit: store.unit)) })
        if focused == nil || !fields.contains(focused!) { focused = fields.first }
    }
}

extension WatchSetField {
    /// Kratka oznaka jedinice ispod vrijednosti.
    func unitLabel(unit: WeightUnit) -> String {
        switch self {
        case .weight: unit.symbol
        case .extraWeight: unit.symbol
        case .reps: String(localized: "pon.")
        case .duration: String(localized: "min:s")
        case .distance: "m"
        }
    }
}

// MARK: - Odmor

/// Odmor: veliko odbrojavanje, −10 / +10 i preskakanje. Na kraju sat zavibrira.
struct WatchRestView: View {
    let timer: RestTimer
    @Environment(WatchWorkoutStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 6) {
            Text("Odmor")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(timerInterval: Date.now...max(timer.endsAt, Date.now), countsDown: true)
                .font(.system(size: countdownSize, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(Text("Preostali odmor"))
            if let next = store.currentSet {
                Text(nextText(exercise: next.exercise, set: next.set))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            HStack {
                Button("−10 s") { store.adjustRest(by: -10) }
                    .accessibilityLabel(Text("Skrati odmor za 10 sekundi"))
                Button("Preskoči odmor", systemImage: "forward.end.fill") { store.skipRest() }
                    .labelStyle(.iconOnly)
                Button("+10 s") { store.adjustRest(by: 10) }
                    .accessibilityLabel(Text("Produlji odmor za 10 sekundi"))
            }
            .font(.footnote)
        }
        .scenePadding(.horizontal)
    }

    private func nextText(exercise: ExerciseSnapshot, set: SetSnapshot) -> String {
        let values = WatchSetField.fields(for: exercise.inputType)
            .map { "\($0.text(in: set, unit: store.unit)) \($0.unitLabel(unit: store.unit))" }
            .joined(separator: " × ")
        return "\(exercise.exercise.name): \(values)"
    }
}
