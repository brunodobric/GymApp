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

/// Trenutna vježba i serija, raspoređeni po cijeloj visini: gore trajanje, puls i vježba, u sredini
/// vrijednosti (Digital Crown, dodir bira polje) i "prošli put", a pri dnu kvačica.
/// Serija s trajanjem (kardio, izdržaj) umjesto krune ima štopericu.
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
        let usesStopwatch = WatchSetField.fields(for: exercise.inputType).contains(.duration)
        return VStack(alignment: .leading, spacing: 4) {
            header(exercise: exercise, set: set)
            Spacer(minLength: 2)
            if usesStopwatch {
                WatchStopwatchView(exercise: exercise, set: set)
            } else {
                WatchSetValuesEditor(exercise: exercise, set: set)
                previousLine(exercise: exercise, set: set)
                Spacer(minLength: 2)
                HStack {
                    Button("Prethodna vježba", systemImage: "chevron.backward") { store.moveExercise(by: -1) }
                        .disabled(!store.canMoveExercise(by: -1))
                    Button("Završi seriju", systemImage: "checkmark") { store.completeCurrentSet() }
                        .buttonStyle(.borderedProminent)
                        // Zelena znači gotovu seriju (kao kvačica na iPhoneu), pa ne prati akcent.
                        .tint(.green)
                        .layoutPriority(1)
                    Button("Sljedeća vježba", systemImage: "chevron.forward") { store.moveExercise(by: 1) }
                        .disabled(!store.canMoveExercise(by: 1))
                }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
            }
        }
        .scenePadding(.horizontal)
        .padding(.bottom, 6)
    }

    private func header(exercise: ExerciseSnapshot, set: SetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WatchHeaderMetrics()
            HStack(spacing: 5) {
                if store.isCardio(exercise) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Kardio"))
                }
                Text(exercise.exercise.name)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .font(.cardTitle)
            HStack(spacing: 6) {
                WatchSetBadge(number: exercise.workingNumber(ofSet: set.id), isCurrent: true)
                Text(setLabel(exercise: exercise, set: set))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.footnote)
        }
    }

    private func setLabel(exercise: ExerciseSnapshot, set: SetSnapshot) -> String {
        let ordered = exercise.orderedSets
        let number = (ordered.firstIndex { $0.id == set.id } ?? 0) + 1
        let base = String(localized: "Serija \(number) od \(ordered.count)")
        return set.kind == .warmUp ? base + " · " + String(localized: "zagrijavanje") : base
    }

    @ViewBuilder
    private func previousLine(exercise: ExerciseSnapshot, set: SetSnapshot) -> some View {
        if let previous = store.previousSet(of: set, in: exercise) {
            let text = WatchSetField.fields(for: exercise.inputType)
                .map { $0.text(in: previous, unit: store.unit) }
                .joined(separator: " × ")
            Label(String(localized: "Prošli put \(text)"), systemImage: "arrow.counterclockwise")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }

    /// Vježba nema nezavršenih serija: dodaj seriju, idi dalje ili završi trening.
    private var exerciseDone: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchHeaderMetrics()
                if let exercise = store.currentExercise {
                    Text(exercise.exercise.name).font(.cardTitle).multilineTextAlignment(.center)
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

/// Vrijednosti serije. Odabrana vrijednost je obrubljena naglasnom bojom, a kruna je mijenja u koracima polja.
struct WatchSetValuesEditor: View {
    let exercise: ExerciseSnapshot
    let set: SetSnapshot
    /// Polja koja se prikazuju; zadano sva polja vrste unosa (štoperica prikazuje samo udaljenost).
    var only: [WatchSetField]?
    var compact = false

    @Environment(WatchWorkoutStore.self) private var store
    @FocusState private var focused: WatchSetField?
    @State private var values: [WatchSetField: Double] = [:]

    private var fields: [WatchSetField] { only ?? WatchSetField.fields(for: exercise.inputType) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                if index > 0 {
                    Text(verbatim: fields == [.duration, .distance] ? "·" : "×")
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
        let isFocused = focused == field
        return VStack(spacing: 0) {
            Text(field.text(in: set, unit: store.unit))
                .font(compact ? Font.metricSmall : Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(field.unitLabel(unit: store.unit))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, compact ? 2 : 6)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.4)),
                    lineWidth: isFocused ? 2.5 : 1
                )
        }
        .focusable()
        .focused($focused, equals: field)
        .digitalCrownRotation(
            binding, from: range.lowerBound, through: range.upperBound,
            // Težina ide u koraku vježbe s iPhonea (oprema ili vlastiti korak), isto kao kotačić tamo.
            by: field.step(unit: store.unit, weightStep: exercise.weightStep),
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

// MARK: - Štoperica

/// Serija s trajanjem: štoperica broji sama, a kvačica upisuje izmjereno vrijeme. Prije pokretanja se
/// prikazuje upisano (ciljno) trajanje. Udaljenost se i dalje mijenja krunom.
struct WatchStopwatchView: View {
    let exercise: ExerciseSnapshot
    let set: SetSnapshot
    @Environment(WatchWorkoutStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 44

    private var stopwatch: Stopwatch? {
        store.stopwatch.flatMap { $0.setID == set.id ? $0 : nil }
    }

    private var hasDistance: Bool {
        WatchSetField.fields(for: exercise.inputType).contains(.distance)
    }

    var body: some View {
        VStack(spacing: 4) {
            elapsed
                .font(.system(size: timeSize, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
            if (set.durationSeconds ?? 0) > 0, stopwatch != nil {
                Text("Cilj \(WatchSetField.duration.text(in: set, unit: store.unit))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            HStack(spacing: 6) {
                if hasDistance {
                    WatchSetValuesEditor(exercise: exercise, set: set, only: [.distance], compact: true)
                }
                Button {
                    store.toggleStopwatch(for: set.id)
                } label: {
                    Image(systemName: stopwatch?.isRunning == true ? "pause.fill" : "play.fill")
                        .frame(maxWidth: hasDistance ? nil : .infinity)
                }
                .accessibilityLabel(stopwatch?.isRunning == true ? Text("Pauza") : Text("Pokreni"))
                Button("Završi seriju", systemImage: "checkmark") { store.completeCurrentSet() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
            .font(.title3.weight(.semibold))
        }
    }

    @ViewBuilder
    private var elapsed: some View {
        if let stopwatch, stopwatch.isRunning {
            Text(stopwatch.displayStart(at: .now), style: .timer)
                .multilineTextAlignment(.center)
        } else if let stopwatch {
            Text(Duration.seconds(stopwatch.elapsedSeconds(at: .now)).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text(WatchSetField.duration.text(in: set, unit: store.unit))
        }
    }
}

// MARK: - Odmor

/// Odmor: krug koji se prazni oko velikog odbrojavanja, sljedeća serija u krugu, a pri dnu −10 / +10
/// i preskakanje. Lagani dodir 10 s prije kraja, a na kraju sat zavibrira.
struct WatchRestView: View {
    let timer: RestTimer
    @Environment(WatchWorkoutStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 4) {
            WatchHeaderMetrics()
                .frame(maxWidth: .infinity, alignment: .leading)
            ring
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button("−10 s") { store.adjustRest(by: -10) }
                    .accessibilityLabel(Text("Skrati odmor za 10 sekundi"))
                Button("Preskoči odmor", systemImage: "forward.end.fill") { store.skipRest() }
                    .labelStyle(.iconOnly)
                Button("+10 s") { store.adjustRest(by: 10) }
                    .accessibilityLabel(Text("Produlji odmor za 10 sekundi"))
            }
            .font(.footnote.weight(.semibold))
        }
        .scenePadding(.horizontal)
        .padding(.bottom, 6)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 8)
            // Krug se osvježava jednom u sekundi, a animacija ga glatko prazni između otkucaja.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Circle()
                    .trim(from: 0, to: 1 - timer.progress(at: context.date))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: context.date)
            }
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text("Odmor")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(timerInterval: Date.now...max(timer.endsAt, Date.now), countsDown: true)
                    .font(.system(size: countdownSize, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(Text("Preostali odmor"))
                if let next = store.currentSet {
                    Text(nextText(exercise: next.exercise, set: next.set))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(4)
    }

    private func nextText(exercise: ExerciseSnapshot, set: SetSnapshot) -> String {
        let values = WatchSetField.fields(for: exercise.inputType)
            .map { $0.text(in: set, unit: store.unit) }
            .joined(separator: " × ")
        return String(localized: "Sljedeće: \(values)")
    }
}
