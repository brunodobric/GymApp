import Models
import Planning
import SwiftData
import SwiftUI

/// Uređivač rasporeda: niz treninga i dana odmora, trajanje, aktivnost i podsjetnici.
///
/// Treninzi se dodaju iz izbornika ili iz bočne ploče (inspector), gdje se mogu odabrati više odjednom
/// ili na iPadu povući na željeno mjesto u nizu.
struct ScheduleEditorScreen: View {
    @Bindable var schedule: Schedule
    @State private var showsTemplates = false
    /// Trening stvoren iz rasporeda, otvara se u uređivaču da mu se dodaju vježbe.
    @State private var createdTemplate: WorkoutTemplate?

    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @Query private var overrides: [CycleOverride]

    private var engine: ScheduleEngine { ScheduleEngine(context: context) }

    var body: some View {
        List {
            Section("Naziv") {
                TextField("Naziv rasporeda", text: $schedule.name)
                Toggle("Aktivan", isOn: Binding(
                    get: { schedule.isActive },
                    set: { try? engine.setActive($0, for: schedule); refreshReminders() }
                ))
            }
            nextSection
            sequenceSection
            durationSection
            reminderSection
        }
        .navigationTitle(schedule.name.isEmpty ? String(localized: "Raspored") : schedule.name)
        .navigationBarTitleDisplayMode(.inline)
        // Ploča s treninzima otvara se samo gumbom Odaberi više treninga (i ⌘K), a zatvara gumbom Zatvori.
        .toolbar { EditButton() }
        .commandShortcut("Odaberi više treninga", key: "k") { showsTemplates = true }
        .planningPanel(isPresented: $showsTemplates, minWidth: 280, idealWidth: 320, maxWidth: 420) {
            TemplateListPanel(isPresented: $showsTemplates) { insert($0, at: nil) }
        }
        .navigationDestination(item: $createdTemplate) { TemplateEditorScreen(template: $0) }
        .onChange(of: overrides.count) { _, _ in refreshReminders() }
        .onDisappear {
            try? context.save()
            refreshReminders()
        }
    }

    // MARK: Sljedeći trening

    @ViewBuilder
    private var nextSection: some View {
        Section("Sljedeće") {
            if let planned = try? engine.nextWorkout(of: schedule) {
                NavigationLink {
                    UpcomingWorkoutScreen(schedule: schedule)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(planned.template.name)
                        Text("Ciklus \(planned.cycle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                // Preskočeni trening se može vratiti dok je ciklus u tijeku (podnožje Sljedećeg treninga to obećaje).
                ForEach((try? engine.skippedWorkouts(of: schedule)) ?? []) { skipped in
                    HStack {
                        Label {
                            Text("Preskočeno: \(skipped.templateName)")
                        } icon: {
                            Image(systemName: "forward.end")
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("Vrati") {
                            try? engine.unskip(skipped.change, in: schedule)
                            refreshReminders()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else if schedule.isActive {
                Text("Dodaj barem jedan trening u niz.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Raspored nije aktivan.")
                    .foregroundStyle(.secondary)
                Button("Pokreni ispočetka", systemImage: "arrow.counterclockwise") {
                    try? engine.restart(schedule)
                    refreshReminders()
                }
            }
        }
    }

    // MARK: Niz

    private var sequenceSection: some View {
        Section("Niz") {
            ForEach(schedule.orderedItems) { item in
                HStack {
                    Image(systemName: symbol(of: item))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    Text(title(of: item))
                    Spacer()
                    if isCurrent(item) {
                        Text("Sljedeće")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .background(Color.accentColor.opacity(0.2), in: .capsule)
                    }
                }
            }
            .onMove { source, destination in
                try? engine.moveItems(in: schedule, from: source, to: destination)
            }
            .onDelete { offsets in
                let list = schedule.orderedItems
                for index in offsets { try? engine.removeItem(list[index]) }
            }
            // Trening povučen iz ploče umeće se na mjesto gdje je pušten.
            .dropDestination(for: String.self) { payloads, index in
                insert(droppedTemplates(payloads), at: index)
            }
            // Bez ijednog treninga gumb odmah stvara novi, jer onemogućen izbornik u listi izgleda
            // kao da radi, a dodir ništa ne napravi.
            if templates.isEmpty {
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
            Button("Dodaj dan odmora", systemImage: "moon.zzz") { _ = try? engine.addRestDay(to: schedule) }
        }
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

    private func symbol(of item: ScheduleItem) -> String {
        if item.kind == .restDay { return "moon.zzz" }
        let template = templates.first { $0.id == item.workoutTemplateId }
        return template?.kind == .cardio ? (template?.cardioPlan?.activity.symbol ?? "figure.run") : "dumbbell"
    }

    private func isCurrent(_ item: ScheduleItem) -> Bool {
        guard schedule.isActive, let planned = try? engine.nextWorkout(of: schedule) else { return false }
        return planned.item.id == item.id
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
            Text("Podsjetnici")
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
