import Models
import SwiftData
import SwiftUI
import Units

/// Uređivač kardio treninga: vrsta, zagrijavanje, blokovi intervala i hlađenje.
/// Kardio trening se pokreće na satu u aplikaciji Workout, a kad je u rasporedu, Apolon ga tamo zakazuje.
///
/// U kartici Rasporedi trening se otvara samo za prikaz, a uređuje se nakon gumba Uredi (`PlanningEditing`).
struct CardioTemplateEditor: View {
    @Bindable var template: WorkoutTemplate
    /// Prikaz ili uređivanje. Bez toga trening se uvijek uređuje.
    var editing: PlanningEditing?

    @Environment(\.modelContext) private var context
    @State private var plan: CardioPlan

    init(template: WorkoutTemplate, editing: PlanningEditing? = nil) {
        self.template = template
        self.editing = editing
        _plan = State(initialValue: template.cardioPlan ?? CardioPreset.easyRun.plan)
    }

    private var isEditing: Bool { editing?.isEditing ?? true }

    var body: some View {
        List {
            Section("Naziv") {
                TextField("Naziv treninga", text: $template.name)
            }
            .disabled(!isEditing)
            Section("Vrsta") {
                Picker("Aktivnost", selection: $plan.activity) {
                    ForEach(CardioActivity.allCases, id: \.self) { activity in
                        Label(activity.title, systemImage: activity.symbol).tag(activity)
                    }
                }
                Picker("Mjesto", selection: $plan.location) {
                    ForEach(CardioLocation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .disabled(!isEditing)
            OptionalGoalSection(title: "Zagrijavanje", goal: $plan.warmup)
                .disabled(!isEditing)
            Section {
                ForEach($plan.intervals) { $interval in
                    NavigationLink {
                        CardioIntervalEditor(interval: $interval)
                            .disabled(!isEditing)
                    } label: {
                        Text(CardioText.interval(interval))
                    }
                }
                // U prikazu nema premještanja ni brisanja.
                .onMove(perform: isEditing ? moveIntervals : nil)
                .onDelete(perform: isEditing ? deleteIntervals : nil)
                if isEditing {
                    Button("Dodaj blok", systemImage: "plus") {
                        plan.intervals.append(CardioInterval(work: .time(seconds: 60), recovery: .time(seconds: 60), repeats: 4))
                    }
                }
            } header: {
                Text("Blokovi")
            } footer: {
                Text("Blok je rad i oporavak, ponovljeni zadani broj puta. Obično trčanje je jedan blok bez oporavka.")
            }
            OptionalGoalSection(title: "Hlađenje", goal: $plan.cooldown)
                .disabled(!isEditing)
            Section {
                Label {
                    Text("Trening se pokreće na satu u aplikaciji Workout. U rasporedu ga Apolon zakazuje na sat za termin podsjetnika.")
                } icon: {
                    Image(systemName: "applewatch")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(template.name.isEmpty ? String(localized: "Kardio") : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Predložak", systemImage: "square.stack") {
                        ForEach(CardioPreset.allCases) { preset in
                            Button(preset.title) { plan = preset.plan }
                        }
                    }
                }
            }
        }
        .planningEditToolbar(editing)
        .onChange(of: plan) { _, newValue in template.cardioPlan = newValue }
        // Izlazak bez spremanja vraća trening iz snimke, a plan na ekranu ga prati.
        .onChange(of: template.cardioPlanRaw) { _, _ in
            if let saved = template.cardioPlan, saved != plan { plan = saved }
        }
        .onDisappear {
            try? context.save()
            // Promjena plana mijenja i plan zakazan na satu.
            ReminderScheduler.refresh(context: context)
        }
    }
}

extension CardioTemplateEditor {
    private func moveIntervals(from source: IndexSet, to destination: Int) {
        plan.intervals.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteIntervals(at offsets: IndexSet) {
        // Plan mora imati barem jedan blok.
        guard plan.intervals.count > offsets.count else { return }
        plan.intervals.remove(atOffsets: offsets)
    }
}

/// Zagrijavanje ili hlađenje: uključeno ili ne, i cilj.
private struct OptionalGoalSection: View {
    let title: LocalizedStringKey
    @Binding var goal: CardioGoal?

    var body: some View {
        Section(title) {
            Toggle(title, isOn: Binding(
                get: { goal != nil },
                set: { goal = $0 ? .time(seconds: 5 * 60) : nil }
            ))
            if let current = goal {
                CardioGoalEditor(goal: Binding(get: { current }, set: { goal = $0 }))
            }
        }
    }
}

/// Jedan blok: broj ponavljanja, rad i oporavak.
private struct CardioIntervalEditor: View {
    @Binding var interval: CardioInterval

    var body: some View {
        List {
            Section {
                Stepper(value: $interval.repeats, in: 1...50) {
                    Text("Ponavljanja: \(interval.repeats)")
                }
            }
            Section("Rad") {
                CardioGoalEditor(goal: $interval.work)
            }
            Section("Oporavak") {
                Toggle("Oporavak", isOn: Binding(
                    get: { interval.recovery != nil },
                    set: { interval.recovery = $0 ? .time(seconds: 60) : nil }
                ))
                if let recovery = interval.recovery {
                    CardioGoalEditor(goal: Binding(get: { recovery }, set: { interval.recovery = $0 }))
                }
            }
        }
        .navigationTitle("Blok")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Cilj koraka: bez cilja, vrijeme (minute i sekunde) ili udaljenost (km).
struct CardioGoalEditor: View {
    @Binding var goal: CardioGoal

    private enum Kind: Hashable {
        case open, time, distance
    }

    @State private var distanceText = ""

    private var kind: Kind {
        switch goal {
        case .open: .open
        case .time: .time
        case .distance: .distance
        }
    }

    var body: some View {
        Picker("Cilj", selection: Binding(get: { kind }, set: change(to:))) {
            Text("Vrijeme").tag(Kind.time)
            Text("Udaljenost").tag(Kind.distance)
            Text("Bez cilja").tag(Kind.open)
        }
        .pickerStyle(.segmented)
        switch goal {
        case .open:
            EmptyView()
        case .time(let seconds):
            timeSteppers(seconds: Int(seconds.rounded()))
        case .distance(let meters):
            HStack {
                Text("Udaljenost")
                Spacer()
                TextField("km", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                Text("km").foregroundStyle(.secondary)
            }
            .onAppear { distanceText = NumberInput.format(meters / 1_000) }
            .onChange(of: distanceText) { _, text in
                if let kilometers = NumberInput.parse(text), kilometers > 0 { goal = .distance(meters: kilometers * 1_000) }
            }
        }
    }

    @ViewBuilder
    private func timeSteppers(seconds: Int) -> some View {
        Stepper(value: Binding(
            get: { seconds / 60 },
            set: { goal = .time(seconds: Double(max($0 * 60 + seconds % 60, 15))) }
        ), in: 0...600) {
            Text("Minute: \(seconds / 60)")
        }
        Stepper(value: Binding(
            get: { seconds % 60 },
            set: { goal = .time(seconds: Double(max((seconds / 60) * 60 + $0, 15))) }
        ), in: 0...45, step: 15) {
            Text("Sekunde: \(seconds % 60)")
        }
    }

    private func change(to kind: Kind) {
        switch kind {
        case .open: goal = .open
        case .time: goal = .time(seconds: 10 * 60)
        case .distance:
            goal = .distance(meters: 1_000)
            distanceText = NumberInput.format(1)
        }
    }
}
