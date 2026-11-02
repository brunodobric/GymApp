import Models
import Planning
import SwiftData
import SwiftUI

/// Kartica Rasporedi: rasporedi i treninzi (predlošci), uz gotove programe.
struct SchedulesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Schedule.createdAt) private var schedules: [Schedule]
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @State private var path = NavigationPath()
    @State private var showsPrograms = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Rasporedi") {
                    if schedules.isEmpty {
                        Text("Još nema rasporeda. Dodaj gotov program ili složi vlastiti.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(schedules) { schedule in
                        NavigationLink(value: schedule) { ScheduleRow(schedule: schedule) }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(schedules[index]) }
                        try? context.save()
                        ReminderScheduler.refresh(context: context)
                    }
                }
                Section("Treninzi") {
                    if templates.isEmpty {
                        Text("Još nema treninga.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(templates) { template in
                        NavigationLink(value: template) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                Text("\((template.exercises ?? []).count) vježbi")
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
                        Button("Gotovi programi", systemImage: "square.stack.3d.up") { showsPrograms = true }
                    }
                }
            }
            .navigationDestination(for: Schedule.self) { ScheduleEditorScreen(schedule: $0) }
            .navigationDestination(for: WorkoutTemplate.self) { TemplateEditorScreen(template: $0) }
            .sheet(isPresented: $showsPrograms) { ProgramsScreen() }
            .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("U redu") {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func newSchedule() {
        do {
            let schedule = try ScheduleEngine(context: context).createSchedule(name: String(localized: "Novi raspored"))
            path.append(schedule)
        } catch {
            errorText = String(localized: "Raspored se nije mogao stvoriti.")
        }
    }

    private func newTemplate() {
        do {
            let template = try TemplateEngine(context: context).createTemplate(name: String(localized: "Novi trening"))
            path.append(template)
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
