import Models
import Planning
import SwiftData
import SwiftUI

/// Odabrana stavka u popisu rasporeda i treninga.
enum PlanningSelection: Hashable {
    case schedule(UUID)
    case template(UUID)

    var id: UUID {
        switch self {
        case .schedule(let id), .template(let id): id
        }
    }
}

/// Kartica Rasporedi: rasporedi i treninzi (predlošci), uz gotove programe.
///
/// U regular širini (iPad) popis i uređivač stoje jedan pored drugog (`NavigationSplitView`).
/// U compact širini split view se sklapa u običan stog.
struct SchedulesScreen: View {
    /// Kartica Rasporedi je otvorena. Kad korisnik ode na drugu karticu, uređivanje se sprema,
    /// a povratak uvijek počinje od popisa.
    var isSelectedTab = true

    @Environment(\.modelContext) private var context
    @Query(sort: \Schedule.createdAt) private var schedules: [Schedule]
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @State private var selection: PlanningSelection?
    @State private var showsPrograms = false
    @State private var errorText: String?
    /// Stavka koja je u načinu uređivanja (Uredi, ili upravo stvorena). Ostale se samo prikazuju.
    @State private var editing: PlanningSelection?
    /// Stavka u uređivanju je nova: izlazak bez spremanja je briše.
    @State private var editingIsNew = false
    @State private var scheduleSnapshot: ScheduleSnapshot?
    @State private var templateSnapshot: TemplateSnapshot?
    /// Kamo se ide kad korisnik odgovori na pitanje o nespremljenim promjenama.
    @State private var pendingSelection: PlanningSelection?
    /// Stavka stvorena dok je prethodna čekala odgovor: nakon pitanja odmah je u uređivanju.
    @State private var pendingIsNew = false
    @State private var asksToSave = false

    var body: some View {
        NavigationSplitView {
            planningList
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            NavigationStack {
                detail
            }
            // Novi odabir počinje s praznim stogom (bez otvorene vježbe prethodnog treninga).
            .id(selection)
        }
        // Obrisana stavka više nije odabrana, pa se na iPhoneu vraća popis.
        .onChange(of: schedules.map(\.id) + templates.map(\.id)) { _, ids in
            switch selection {
            case .schedule(let id), .template(let id):
                if !ids.contains(id) { selection = nil }
            case nil:
                break
            }
            if let id = editing?.id, !ids.contains(id) { clearEditing() }
        }
        .onChange(of: isSelectedTab) { _, isSelected in
            guard !isSelected else { return }
            if editing != nil { finishEditing() }
            asksToSave = false
            pendingSelection = nil
            pendingIsNew = false
            selection = nil
        }
        .alert(saveTitle, isPresented: $asksToSave) {
            Button("Spremi") {
                finishEditing()
                finishLeaving()
            }
            Button("Izađi bez spremanja", role: .destructive) {
                discardEditing()
                finishLeaving()
            }
            Button("Odustani", role: .cancel) {
                // Stavka stvorena dok se čekao odgovor ne smije ostati kao tihi višak.
                if pendingIsNew, let pendingSelection { delete(pendingSelection) }
                pendingSelection = nil
                pendingIsNew = false
            }
        } message: {
            Text(saveMessage)
        }
    }

    // MARK: Prikaz i uređivanje

    private var saveTitle: LocalizedStringKey {
        guard editingIsNew else { return "Spremiti promjene?" }
        if case .schedule = editing { return "Spremiti raspored?" }
        return "Spremiti trening?"
    }

    private var saveMessage: LocalizedStringKey {
        guard editingIsNew else { return "Promjene još nisu spremljene." }
        if case .schedule = editing { return "Novi raspored još nije spremljen." }
        return "Novi trening još nije spremljen."
    }

    /// Gumbi Uredi i Gotovo te natrag za stavku u detalju.
    private func editControls(for item: PlanningSelection) -> PlanningEditing {
        PlanningEditing(
            isEditing: editing == item,
            onEdit: { beginEditing(item) },
            onDone: { finishEditing() },
            onLeave: { select(nil) }
        )
    }

    private func beginEditing(_ item: PlanningSelection) {
        switch item {
        case .schedule(let id):
            guard let schedule = schedules.first(where: { $0.id == id }) else { return }
            scheduleSnapshot = try? ScheduleSnapshot(schedule, context: context)
        case .template(let id):
            guard let template = templates.first(where: { $0.id == id }) else { return }
            templateSnapshot = TemplateSnapshot(template)
        }
        editing = item
        editingIsNew = false
    }

    private func finishEditing() {
        try? context.save()
        ReminderScheduler.refresh(context: context)
        clearEditing()
    }

    /// Izlazak bez spremanja: nova stavka se briše, postojeća se vraća na stanje prije uređivanja.
    private func discardEditing() {
        guard let editing else { return }
        if editingIsNew {
            delete(editing)
        } else {
            switch editing {
            case .schedule(let id):
                if let schedule = schedules.first(where: { $0.id == id }) {
                    try? scheduleSnapshot?.restore(schedule, in: context)
                }
            case .template(let id):
                if let template = templates.first(where: { $0.id == id }) {
                    try? templateSnapshot?.restore(template, in: context)
                }
            }
            ReminderScheduler.refresh(context: context)
        }
        clearEditing()
    }

    private func clearEditing() {
        editing = nil
        editingIsNew = false
        scheduleSnapshot = nil
        templateSnapshot = nil
    }

    private func delete(_ item: PlanningSelection) {
        switch item {
        case .schedule(let id):
            if let schedule = schedules.first(where: { $0.id == id }) {
                try? ScheduleEngine(context: context).delete(schedule)
            }
        case .template(let id):
            if let template = templates.first(where: { $0.id == id }) {
                try? TemplateEngine(context: context).delete(template)
            }
        }
        ReminderScheduler.refresh(context: context)
    }

    /// Odabir u popisu (i natrag) prolazi ovdje, da se promjene u uređivanju ne izgube ni ne spreme bez pitanja.
    /// `isNew`: stavka je upravo stvorena i otvara se odmah u uređivanju.
    private func select(_ next: PlanningSelection?, isNew: Bool = false) {
        if let editing, next != editing {
            pendingSelection = next
            pendingIsNew = isNew
            asksToSave = true
        } else {
            selection = next
            if isNew, let next {
                editing = next
                editingIsNew = true
            }
        }
    }

    private func finishLeaving() {
        selection = pendingSelection
        if pendingIsNew, let pendingSelection {
            editing = pendingSelection
            editingIsNew = true
        }
        pendingSelection = nil
        pendingIsNew = false
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .schedule(let id):
            if let schedule = schedules.first(where: { $0.id == id }) {
                ScheduleEditorScreen(schedule: schedule, editing: editControls(for: .schedule(id)))
            }
        case .template(let id):
            if let template = templates.first(where: { $0.id == id }) {
                if template.kind == .cardio {
                    CardioTemplateEditor(template: template, editing: editControls(for: .template(id)))
                } else {
                    TemplateEditorScreen(template: template, editing: editControls(for: .template(id)))
                }
            }
        case nil:
            ContentUnavailableView(
                "Odaberi raspored ili trening",
                systemImage: "calendar",
                description: Text("Uređivač odabrane stavke prikazuje se ovdje.")
            )
        }
    }

    private var planningList: some View {
        List(selection: Binding(get: { selection }, set: { select($0) })) {
            Section("Rasporedi") {
                if schedules.isEmpty {
                    Text("Još nema rasporeda. Dodaj gotov program ili složi vlastiti.")
                        .foregroundStyle(.secondary)
                }
                ForEach(schedules) { schedule in
                    NavigationLink(value: PlanningSelection.schedule(schedule.id)) { ScheduleRow(schedule: schedule) }
                }
                .onDelete { offsets in
                    let engine = ScheduleEngine(context: context)
                    for index in offsets { try? engine.delete(schedules[index]) }
                    ReminderScheduler.refresh(context: context)
                }
            }
            Section("Treninzi") {
                if templates.isEmpty {
                    Text("Još nema treninga.")
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    NavigationLink(value: PlanningSelection.template(template.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text(subtitle(of: template))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let engine = TemplateEngine(context: context)
                    for index in offsets { try? engine.delete(templates[index]) }
                    ReminderScheduler.refresh(context: context)
                }
            }
        }
        .navigationTitle("Rasporedi")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Dodaj", systemImage: "plus") {
                    Button("Novi raspored", systemImage: "calendar.badge.plus") { newSchedule() }
                    Button("Novi trening", systemImage: "dumbbell") { newTemplate() }
                    Menu("Novi kardio trening", systemImage: "figure.run") {
                        ForEach(CardioPreset.allCases) { preset in
                            Button(preset.title) { newCardioTemplate(preset) }
                        }
                    }
                    Button("Gotovi programi", systemImage: "square.stack.3d.up") { showsPrograms = true }
                }
            }
        }
        .sheet(isPresented: $showsPrograms) { ProgramsScreen() }
        .errorAlert($errorText)
    }

    private func newSchedule() {
        do {
            let schedule = try ScheduleEngine(context: context).createSchedule(name: String(localized: "Novi raspored"))
            select(.schedule(schedule.id), isNew: true)
        } catch {
            errorText = String(localized: "Raspored se nije mogao stvoriti.")
        }
    }

    private func subtitle(of template: WorkoutTemplate) -> String {
        if template.kind == .cardio {
            return template.cardioPlan.map(CardioText.summary) ?? String(localized: "Kardio")
        }
        return String(localized: "\((template.exercises ?? []).count) vježbi")
    }

    private func newCardioTemplate(_ preset: CardioPreset) {
        do {
            let template = try TemplateEngine(context: context).createCardioTemplate(name: preset.title, plan: preset.plan)
            select(.template(template.id), isNew: true)
        } catch {
            errorText = String(localized: "Trening se nije mogao stvoriti.")
        }
    }

    private func newTemplate() {
        do {
            let template = try TemplateEngine(context: context).createTemplate(name: String(localized: "Novi trening"))
            select(.template(template.id), isNew: true)
        } catch {
            errorText = String(localized: "Trening se nije mogao stvoriti.")
        }
    }
}

private struct ScheduleRow: View {
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(schedule.name)
                if !schedule.isActive {
                    Text("Neaktivan")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .background(.quaternary, in: .capsule)
                }
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let workouts = (schedule.items ?? []).filter { $0.kind == .workout }.count
        if let cycles = schedule.cycleCount {
            return String(localized: "\(workouts) treninga, ciklus \(min(schedule.currentCycle, cycles)) od \(cycles)")
        }
        return String(localized: "\(workouts) treninga, ciklus \(schedule.currentCycle)")
    }
}
