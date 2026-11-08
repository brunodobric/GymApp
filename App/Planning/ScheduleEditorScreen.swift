import Models
import Planning
import SwiftData
import SwiftUI
import Training

/// Uređivač rasporeda: niz treninga i dana odmora, trajanje, aktivnost i podsjetnici.
///
/// U kartici Rasporedi raspored se otvara samo za prikaz, a uređuje se nakon gumba Uredi (`PlanningEditing`).
///
/// Treninzi se dodaju iz izbornika ili iz bočne ploče (inspector), gdje se mogu odabrati više odjednom
/// ili na iPadu povući na željeno mjesto u nizu.
struct ScheduleEditorScreen: View {
    @Bindable var schedule: Schedule
    /// Prikaz ili uređivanje. Bez toga raspored se uvijek uređuje.
    var editing: PlanningEditing?
    @State private var showsTemplates = false
    /// Trening stvoren iz rasporeda, otvara se u uređivaču da mu se dodaju vježbe.
    @State private var createdTemplate: WorkoutTemplate?
    @State private var asksToSaveCreated = false

    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @Query private var customExercises: [CustomExercise]
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var overrides: [CycleOverride]

    private var engine: ScheduleEngine { ScheduleEngine(context: context) }
    private var isEditing: Bool { editing?.isEditing ?? true }

    var body: some View {
        List {
            Section("Naziv") {
                TextField("Naziv rasporeda", text: $schedule.name)
                    .disabled(!isEditing)
            }
            sequenceSection
            durationSection
            reminderSection
        }
        .planningEditMode(editing)
        .navigationTitle(schedule.name.isEmpty ? String(localized: "Raspored") : schedule.name)
        .navigationBarTitleDisplayMode(.inline)
        .planningEditToolbar(editing)
        // Ploča s treninzima otvara se samo gumbom Odaberi više treninga (i ⌘K), a zatvara gumbom Zatvori.
        .commandShortcut("Odaberi više treninga", key: "k") { if isEditing { showsTemplates = true } }
        .onChange(of: isEditing) { _, isEditing in if !isEditing { showsTemplates = false } }
        .planningPanel(isPresented: $showsTemplates, minWidth: 280, idealWidth: 320, maxWidth: 420) {
            TemplateListPanel(isPresented: $showsTemplates) { insert($0, at: nil) }
        }
        // Novi trening iz niza ima kvačicu kao i novi trening iz popisa, a natrag bez nje pita.
        .navigationDestination(item: $createdTemplate) { template in
            TemplateEditorScreen(template: template, editing: PlanningEditing(
                isEditing: true,
                onEdit: {},
                onDone: {
                    try? context.save()
                    createdTemplate = nil
                },
                onLeave: { asksToSaveCreated = true },
                replacesBackButtonAlways: true
            ))
            .alert("Spremiti trening?", isPresented: $asksToSaveCreated) {
                Button("Spremi") {
                    try? context.save()
                    createdTemplate = nil
                }
                Button("Izađi bez spremanja", role: .destructive) {
                    try? engine.discardNewWorkout(template, from: schedule)
                    refreshReminders()
                    createdTemplate = nil
                }
                Button("Odustani", role: .cancel) {}
            } message: {
                Text("Novi trening još nije spremljen.")
            }
        }
        .onChange(of: overrides.count) { _, _ in refreshReminders() }
        .onDisappear {
            try? context.save()
            refreshReminders()
        }
    }

    // MARK: Niz

    private var sequenceSection: some View {
        let skipped = (try? engine.skippedWorkouts(of: schedule)) ?? []
        return Section("Niz") {
            ForEach(schedule.orderedItems) { item in
                HStack {
                    icon(of: item)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    Text(title(of: item))
                    Spacer()
                    // Preskočeni trening se može vratiti dok je ciklus u tijeku (podnožje Sljedećeg treninga to obećaje).
                    if let skipped = skipped.first(where: { $0.change.scheduleItemId == item.id }) {
                        Text("Preskočeno")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Vrati") {
                            try? engine.unskip(skipped.change, in: schedule)
                            refreshReminders()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            // Premještanje i brisanje samo u uređivanju (crtice i znak za brisanje).
            .onMove(perform: isEditing ? moveItems : nil)
            .onDelete(perform: isEditing ? deleteItems : nil)
            // Trening povučen iz ploče umeće se na mjesto gdje je pušten.
            .dropDestination(for: String.self) { payloads, index in
                guard isEditing else { return }
                insert(droppedTemplates(payloads), at: index)
            }
            if !isEditing {
                if schedule.orderedItems.isEmpty {
                    Text("Još nema treninga u nizu.")
                        .foregroundStyle(.secondary)
                }
            } else if templates.isEmpty {
                // Bez ijednog treninga gumb odmah stvara novi, jer onemogućen izbornik u listi izgleda
                // kao da radi, a dodir ništa ne napravi.
                Button("Novi trening", systemImage: "plus") { addNewWorkout() }
            } else {
                Menu("Dodaj trening", systemImage: "plus") {
                    ForEach(templates) { template in
                        Button(template.name) { try? engine.addWorkout(template, to: schedule) }
                    }
                    Divider()
                    Button("Novi trening", systemImage: "dumbbell") { addNewWorkout() }
                }
                Button("Odaberi više treninga", systemImage: "checklist") { showsTemplates = true }
                    // Puštena na gumb (i u praznom nizu) stavka ide na kraj.
                    .dropDestination(for: String.self) { payloads, _ in
                        let dropped = droppedTemplates(payloads)
                        insert(dropped, at: nil)
                        return !dropped.isEmpty
                    }
            }
            if isEditing {
                Button("Dodaj dan odmora", systemImage: "moon.zzz") { _ = try? engine.addRestDay(to: schedule) }
            }
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        try? engine.moveItems(in: schedule, from: source, to: destination)
    }

    private func deleteItems(at offsets: IndexSet) {
        let list = schedule.orderedItems
        for index in offsets { try? engine.removeItem(list[index]) }
    }

    private func addNewWorkout() {
        guard let template = try? engine.addNewWorkout(named: String(localized: "Novi trening"), to: schedule) else { return }
        refreshReminders()
        createdTemplate = template
    }

    private func droppedTemplates(_ payloads: [String]) -> [WorkoutTemplate] {
        payloads.compactMap(PlanningDrag.templateId(from:)).compactMap { id in templates.first { $0.id == id } }
    }

    private func insert(_ added: [WorkoutTemplate], at index: Int?) {
        guard !added.isEmpty else { return }
        try? engine.insertWorkouts(added, into: schedule, at: index)
        refreshReminders()
    }

    private func title(of item: ScheduleItem) -> String {
        if item.kind == .restDay { return String(localized: "Dan odmora") }
        return templates.first { $0.id == item.workoutTemplateId }?.name ?? String(localized: "Obrisan trening")
    }

    /// Dan odmora je mjesec, trening ikona svoje vrste (`WorkoutKindIcon`).
    @ViewBuilder
    private func icon(of item: ScheduleItem) -> some View {
        if item.kind == .restDay {
            Image(systemName: "moon.zzz")
        } else if let template = templates.first(where: { $0.id == item.workoutTemplateId }) {
            WorkoutKindIcon(
                mix: SessionCardio.mix(of: template, isCardio: catalogStore.isCardio(custom: customExercises)),
                cardioSymbol: template.cardioPlanSymbol
            )
        } else {
            Image(systemName: WorkoutKind.strength.symbol)
        }
    }


    // MARK: Trajanje

    private var durationSection: some View {
        Section {
            Toggle("Traje dok ga ne ugasim", isOn: Binding(
                get: { schedule.cycleCount == nil },
                set: { schedule.cycleCount = $0 ? nil : max(schedule.currentCycle, 1) }
            ))
            if let cycles = schedule.cycleCount {
                Stepper(value: Binding(
                    get: { cycles },
                    set: { schedule.cycleCount = $0 }
                ), in: ScheduleEngine.cycleCountRange(currentCycle: schedule.currentCycle)) {
                    Text("Broj ciklusa: \(cycles)")
                }
            }
        } header: {
            Text("Trajanje")
        } footer: {
            Text("Ciklus završava kad su odrađeni ili preskočeni svi treninzi u nizu. Propušteni dan ništa ne pomiče.")
        }
    }

    // MARK: Podsjetnici

    @ViewBuilder
    private var reminderSection: some View {
        Section {
            Toggle("Aktivan", isOn: Binding(
                get: { schedule.isActive },
                set: { try? engine.setActive($0, for: schedule); refreshReminders() }
            ))
            // Završen ili ugašen raspored kreće od prvog treninga u nizu.
            if !schedule.isActive {
                Button("Pokreni ispočetka", systemImage: "arrow.counterclockwise") {
                    try? engine.restart(schedule)
                    refreshReminders()
                }
            }
            Toggle("Podsjetnici", isOn: Binding(
                get: { schedule.reminderMinutes != nil },
                set: {
                    schedule.reminderMinutes = $0 ? (schedule.reminderMinutes ?? 18 * 60) : nil
                    refreshReminders()
                }
            ))
            if let minutes = schedule.reminderMinutes {
                DatePicker("Vrijeme", selection: Binding(
                    get: { ReminderTime.date(fromMinutes: minutes) },
                    set: {
                        schedule.reminderMinutes = ReminderTime.minutes(from: $0)
                        refreshReminders()
                    }
                ), displayedComponents: .hourAndMinute)
                Picker("Način", selection: Binding(
                    get: { schedule.reminderMode },
                    set: { schedule.reminderMode = $0; refreshReminders() }
                )) {
                    Text("Fleksibilno").tag(ReminderMode.flexible)
                    Text("Fiksni dani").tag(ReminderMode.fixedDays)
                }
                .pickerStyle(.segmented)
                if schedule.reminderMode == .fixedDays {
                    weekdayPicker
                } else {
                    Stepper(value: Binding(
                        get: { schedule.reminderGapDays },
                        set: { schedule.reminderGapDays = $0; refreshReminders() }
                    ), in: 1...7) {
                        Text("\(schedule.reminderGapDays) dana nakon zadnjeg treninga")
                    }
                }
            }
        } header: {
            Text("Aktivnost i podsjetnici")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Podsjetnik se ne šalje ako je taj dan već odrađen trening iz rasporeda, niti tijekom aktivnog treninga.")
                Text("Kardio trening se za termin podsjetnika zakazuje i na sat, u aplikaciju Workout.")
            }
        }
    }

    private var weekdayPicker: some View {
        HStack {
            // Ponedjeljak prvi: Calendar.weekday je 2...7, pa nedjelja (1) na kraju.
            ForEach(ReminderTime.weekdaysFromMonday, id: \.self) { weekday in
                let isOn = schedule.weekdays.contains(weekday)
                Button {
                    schedule.weekdays = ReminderTime.toggling(weekday, in: schedule.weekdays)
                    refreshReminders()
                } label: {
                    Text(Calendar.current.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: .circle)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                // Na ekranu je samo slovo (P, U, S…), a dva P i dva S VoiceOveru ne govore koji je dan.
                .accessibilityLabel(Text(verbatim: Calendar.current.standaloneWeekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func refreshReminders() {
        try? context.save()
        ReminderScheduler.refresh(context: context)
    }
}
