import Models
import Planning
import SwiftData
import SwiftUI

/// Odabrana stavka u popisu rasporeda i treninga.
enum PlanningSelection: Hashable {
    case schedule(UUID)
    case template(UUID)
}

/// Kartica Rasporedi: rasporedi i treninzi (predlošci), uz gotove programe.
///
/// U regular širini (iPad) popis i uređivač stoje jedan pored drugog (`NavigationSplitView`).
/// U compact širini split view se sklapa u običan stog.
struct SchedulesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Schedule.createdAt) private var schedules: [Schedule]
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @State private var selection: PlanningSelection?
    @State private var showsPrograms = false
    @State private var errorText: String?
    /// Novi raspored koji još nije potvrđen gumbom Gotovo.
    @State private var newScheduleId: UUID?
    /// Kamo se ide kad korisnik odgovori na pitanje o nespremljenom novom rasporedu.
    @State private var pendingSelection: PlanningSelection?
    /// Novi raspored stvoren dok je prethodni čekao odgovor (postaje novi tek nakon pitanja).
    @State private var pendingNewScheduleId: UUID?
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
            if let id = newScheduleId, !ids.contains(id) { newScheduleId = nil }
        }
        .alert("Spremiti raspored?", isPresented: $asksToSave) {
            Button("Spremi raspored") {
                newScheduleId = nil
                finishLeaving()
            }
            Button("Izađi bez spremanja", role: .destructive) {
                discardNewSchedule()
                finishLeaving()
            }
            Button("Odustani", role: .cancel) {
                // Raspored stvoren dok se čekao odgovor ne smije ostati kao tihi višak.
                if let id = pendingNewScheduleId, let schedule = schedules.first(where: { $0.id == id }) {
                    try? ScheduleEngine(context: context).delete(schedule)
                }
                pendingSelection = nil
                pendingNewScheduleId = nil
            }
        } message: {
            Text("Novi raspored još nije spremljen.")
        }
    }

    // MARK: Novi raspored

    /// Odabir u popisu (i natrag) prolazi ovdje, da novi raspored ne ostane spremljen bez pitanja.
    private func select(_ next: PlanningSelection?, newSchedule: UUID? = nil) {
        if let id = newScheduleId, next != .schedule(id) {
            pendingSelection = next
            pendingNewScheduleId = newSchedule
            asksToSave = true
        } else {
            selection = next
            if newSchedule != nil { newScheduleId = newSchedule }
        }
    }

    private func finishLeaving() {
        selection = pendingSelection
        newScheduleId = pendingNewScheduleId
        pendingSelection = nil
        pendingNewScheduleId = nil
    }

    private func discardNewSchedule() {
        guard let id = newScheduleId, let schedule = schedules.first(where: { $0.id == id }) else { return }
        try? ScheduleEngine(context: context).delete(schedule)
        ReminderScheduler.refresh(context: context)
        newScheduleId = nil
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .schedule(let id):
            if let schedule = schedules.first(where: { $0.id == id }) {
                ScheduleEditorScreen(
                    schedule: schedule,
                    isNew: schedule.id == newScheduleId,
                    onDone: {
                        newScheduleId = nil
                        selection = nil
                    },
                    onLeave: { select(nil) }
                )
            }
        case .template(let id):
            if let template = templates.first(where: { $0.id == id }) {
                if template.kind == .cardio {
                    CardioTemplateEditor(template: template)
                } else {
                    TemplateEditorScreen(template: template)
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
            select(.schedule(schedule.id), newSchedule: schedule.id)
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
            select(.template(template.id))
        } catch {
            errorText = String(localized: "Trening se nije mogao stvoriti.")
        }
    }

    private func newTemplate() {
        do {
            let template = try TemplateEngine(context: context).createTemplate(name: String(localized: "Novi trening"))
            select(.template(template.id))
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
