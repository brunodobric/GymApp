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
                .font(.headline)
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
                    Text(exercise.exercise.name).font(.headline).multilineTextAlignment(.center)
                }
                Text(store.showsFinishPrompt ? "Sve serije su gotove" : "Vježba je gotova")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if store.showsFinishPrompt {
                    Button("Završi trening", systemImage: "flag.checkered") { store.finish() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
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
                .stroke(focused == field ? Color.green : Color.secondary.opacity(0.4), lineWidth: focused == field ? 2 : 1)
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

    var body: some View {
        VStack(spacing: 6) {
            Text("Odmor")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(timerInterval: Date.now...max(timer.endsAt, Date.now), countsDown: true)
                .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
                Button("Preskoči odmor", systemImage: "forward.end.fill") { store.skipRest() }
                    .labelStyle(.iconOnly)
                Button("+10 s") { store.adjustRest(by: 10) }
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

// MARK: - Kontrole

/// Trajanje, puls i kalorije, uz završetak i odbacivanje treninga.
struct WatchControlsView: View {
    @Environment(WatchWorkoutStore.self) private var store
    @State private var confirmsFinish = false
    @State private var confirmsDiscard = false
    @State private var showsNothingCompleted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let active = store.active {
                    Text(active.startedAt, style: .timer)
                        .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.yellow)
                    if store.isController {
                        metrics
                    } else {
                        Label("Trening vodi iPhone", systemImage: "iphone")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Serije: \(active.completedSetCount)")
                        .font(.footnote)
                }
                Button("Završi", systemImage: "flag.checkered") { confirmsFinish = true }
                    .tint(.green)
                Button("Odbaci", systemImage: "trash", role: .destructive) { confirmsDiscard = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
        .confirmationDialog("Završiti trening?", isPresented: $confirmsFinish) {
            Button("Završi trening") {
                if !store.finish() { showsNothingCompleted = true }
            }
            Button("Nastavi", role: .cancel) {}
        } message: {
            Text("Serije koje nisu označene završenima neće se spremiti.")
        }
        .confirmationDialog("Odbaciti trening?", isPresented: $confirmsDiscard) {
            Button("Odbaci trening", role: .destructive) { store.discard() }
            Button("Nastavi", role: .cancel) {}
        } message: {
            Text("Trening i sve serije bit će obrisani.")
        }
        .alert("Nema završenih serija", isPresented: $showsNothingCompleted) {
            Button("Odbaci trening", role: .destructive) { store.discard() }
            Button("Nastavi", role: .cancel) {}
        } message: {
            Text("Trening bez ijedne završene serije ne može se spremiti.")
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 2) {
            metric(store.health.heartRate, unit: "BPM", symbol: "heart.fill", color: .red)
            metric(store.health.activeEnergyKilocalories, unit: "kcal", symbol: "flame.fill", color: .orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ value: Double?, unit: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(.title3, design: .rounded).monospacedDigit())
            Text(unit).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Popis vježbi

/// Pregled cijelog treninga i prethodnih serija. Dodir na vježbu otvara je na ekranu serije.
struct WatchExerciseListView: View {
    let onSelect: () -> Void
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        List {
            ForEach(store.active?.visibleExercises ?? []) { exercise in
                Section {
                    Button {
                        store.select(exercise.id)
                        onSelect()
                    } label: {
                        HStack {
                            Text(exercise.exercise.name)
                                .font(.headline)
                                .foregroundStyle(exercise.id == store.currentExerciseID ? .green : .primary)
                            if exercise.supersetGroupId != nil {
                                Image(systemName: "link").accessibilityLabel(Text("Superset"))
                            }
                        }
                    }
                    ForEach(exercise.orderedSets) { set in
                        setRow(set, exercise: exercise)
                    }
                    Button("Dodaj seriju", systemImage: "plus") { store.addSet(to: exercise.id) }
                        .font(.footnote)
                }
            }
        }
    }

    private func setRow(_ set: SetSnapshot, exercise: ExerciseSnapshot) -> some View {
        let text = WatchSetField.fields(for: exercise.inputType)
            .map { $0.text(in: set, unit: store.unit) }
            .joined(separator: " × ")
        return HStack {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(set.isCompleted ? .green : .secondary)
            Text(text).monospacedDigit()
            if set.kind == .warmUp {
                Text("Z").font(.caption2).foregroundStyle(.orange)
                    .accessibilityLabel(Text("Zagrijavanje"))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            // Završena serija se dodirom vraća u nezavršene (npr. greškom označena).
            if set.isCompleted {
                store.uncomplete(set.id)
            } else {
                store.select(exercise.id)
                onSelect()
            }
        }
    }
}

// MARK: - Sažetak

struct WatchSummaryView: View {
    let summary: WatchWorkoutStore.Summary
    let onClose: () -> Void
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.name).font(.headline)
                row("Trajanje", Duration.seconds(summary.duration).formatted(.time(pattern: .hourMinuteSecond)))
                row("Serije", "\(summary.completedSets)")
                if summary.volumeKg > 0 {
                    row("Volumen", WeightFormatter(unit: store.unit).string(fromKilograms: summary.volumeKg))
                }
                if let energy = summary.activeEnergyKilocalories {
                    row("Kalorije", "\(Int(energy.rounded())) kcal")
                }
                if let heartRate = summary.averageHeartRate {
                    row("Prosječni puls", "\(Int(heartRate.rounded())) BPM")
                }
                Button("Zatvori", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).monospacedDigit())
        }
    }
}
