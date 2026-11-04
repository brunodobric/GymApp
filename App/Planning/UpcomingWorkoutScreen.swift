import Catalog
import Models
import Planning
import SwiftData
import SwiftUI

/// Sljedeći trening rasporeda s privremenim izmjenama samo za ovaj ciklus:
/// preskoči trening, izbaci vježbu ili zamijeni vježbu. Izmjene se mogu poništiti dok trening nije završen.
/// Kardio trening se ne pokreće ovdje: zaslon pokazuje plan i uputu za pokretanje na satu (faza 10).
/// Ovaj zaslon otvara i dodir na podsjetnik rasporeda.
struct UpcomingWorkoutScreen: View {
    let schedule: Schedule

    @Environment(\.modelContext) private var context
    /// Služi samo da se zaslon osvježi kad se izmjene promijene.
    @Query private var overrides: [CycleOverride]
    @State private var replacing: PlannedExercise?
    @State private var presentedSession: Session?
    @State private var errorText: String?

    private var engine: ScheduleEngine { ScheduleEngine(context: context) }

    var body: some View {
        List {
            if let planned = try? engine.nextWorkout(of: schedule) {
                content(for: planned)
            } else {
                ContentUnavailableView("Nema sljedećeg treninga", systemImage: "calendar.badge.checkmark")
            }
        }
        .navigationTitle("Sljedeći trening")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $replacing) { target in
            ExercisePickerSheet(title: "Zamijeni vježbu") { summary, inputType in
                replace(target, with: summary.ref, inputType: inputType)
            }
        }
        .fullScreenCover(item: $presentedSession) { session in
            ActiveWorkoutScreen(session: session)
        }
        .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("U redu") {}
        } message: {
            Text(errorText ?? "")
        }
        .id(overrides.count)
    }

    @ViewBuilder
    private func content(for planned: PlannedWorkout) -> some View {
        if planned.template.kind == .cardio {
            cardioContent(for: planned)
        } else {
            strengthContent(for: planned)
        }
    }

    @ViewBuilder
    private func cardioContent(for planned: PlannedWorkout) -> some View {
        Section {
            Text(planned.template.name).font(.headline)
            Text("\(schedule.name), ciklus \(planned.cycle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let plan = planned.template.cardioPlan {
            Section("Plan") {
                LabeledContent("Aktivnost") {
                    Label(plan.activity.title, systemImage: plan.activity.symbol)
                }
                LabeledContent("Mjesto", value: plan.location.title)
                if let warmup = plan.warmup {
                    LabeledContent("Zagrijavanje", value: CardioText.goal(warmup))
                }
                ForEach(plan.intervals) { interval in
                    LabeledContent("Blok", value: CardioText.interval(interval))
                }
                if let cooldown = plan.cooldown {
                    LabeledContent("Hlađenje", value: CardioText.goal(cooldown))
                }
            }
        }
        CardioWatchSection(planned: planned)
        skipSection
    }

    @ViewBuilder
    private func strengthContent(for planned: PlannedWorkout) -> some View {
        Section {
            Text(planned.template.name).font(.headline)
            Text("\(schedule.name), ciklus \(planned.cycle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Započni trening", systemImage: "play.fill") { start(planned) }
        }
        Section("Vježbe") {
            ForEach(planned.exercises, id: \.source) { exercise in
                HStack {
                    VStack(alignment: .leading) {
                        Text(exercise.ref.name)
                        if exercise.isReplacement {
                            Text("Zamijenjeno u ovom ciklusu")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }
                .swipeActions {
                    Button("Izbaci", systemImage: "minus.circle", role: .destructive) { remove(exercise, from: planned) }
                    Button("Zamijeni", systemImage: "arrow.left.arrow.right") { replacing = exercise }
                        .tint(.indigo)
                }
            }
        }
        let changes = currentChanges(for: planned)
        if !changes.isEmpty {
            Section {
                ForEach(changes, id: \.id) { change in
                    HStack {
                        Text(label(of: change, in: planned))
                        Spacer()
                        Button("Poništi") { undo(change) }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Izmjene samo za ovaj ciklus")
            } footer: {
                Text("Raspored i trening ostaju nepromijenjeni za sljedeće cikluse.")
            }
        }
        skipSection
    }

    private var skipSection: some View {
        Section {
            Button("Preskoči ovaj trening", systemImage: "forward.end") {
                _ = try? engine.skipNextWorkout(of: schedule)
                ReminderScheduler.refresh(context: context)
            }
        } footer: {
            Text("Preskočeni trening se ne računa u ovom ciklusu. Poništiti ga možeš u uređivaču rasporeda dok je ciklus u tijeku.")
        }
    }

    // MARK: Izmjene

    private func currentChanges(for planned: PlannedWorkout) -> [CycleOverride] {
        ((try? engine.overrides(of: schedule, cycle: planned.cycle)) ?? [])
            .filter { $0.scheduleItemId == planned.item.id && $0.kind != .skipWorkout }
    }

    private func label(of change: CycleOverride, in planned: PlannedWorkout) -> String {
        let original = planned.template.orderedExercises.first { $0.exercise.key == change.targetExerciseKey }?.exerciseName ?? ""
        switch change.kind {
        case .removeExercise: return String(localized: "Izbačeno: \(original)")
        case .replaceExercise: return String(localized: "\(original) → \(change.replacementName ?? "")")
        case .skipWorkout: return ""
        }
    }

    private func original(of exercise: PlannedExercise, in planned: PlannedWorkout) -> TemplateExercise? {
        planned.template.orderedExercises.first { $0.id == exercise.source }
    }

    private func remove(_ exercise: PlannedExercise, from planned: PlannedWorkout) {
        guard let source = original(of: exercise, in: planned) else { return }
        _ = try? engine.removeExercise(source, from: planned)
    }

    private func replace(_ target: PlannedExercise, with ref: ExerciseRef, inputType: ExerciseInputType) {
        guard let planned = try? engine.nextWorkout(of: schedule), let source = original(of: target, in: planned) else { return }
        _ = try? engine.replaceExercise(source, with: ref, inputType: inputType, in: planned)
    }

    private func undo(_ change: CycleOverride) {
        try? engine.undo(change)
    }

    private func start(_ planned: PlannedWorkout) {
        do {
            presentedSession = try PerformanceSignpost.measure("WorkoutStart") {
                try TemplateStarter(context: context).start(planned)
            }
            ReminderScheduler.refresh(context: context)
        } catch {
            errorText = String(localized: "Trening se nije mogao pokrenuti.")
        }
    }
}

/// Stanje plana na satu i gumb za zakazivanje kad plan još nije na satu.
private struct CardioWatchSection: View {
    let planned: PlannedWorkout

    @Environment(\.modelContext) private var context
    @State private var isScheduling = false
    @State private var failed = false

    private var scheduler: CardioWorkoutScheduler { .shared }

    var body: some View {
        Section {
            if !scheduler.isSupported {
                Label("Za ovaj trening treba Apple Watch uparen s ovim iPhoneom.", systemImage: "applewatch.slash")
            } else if planned.template.cardioPlan?.isValid != true {
                Label("Plan nije potpun. Uredi trening i dodaj barem jedan blok.", systemImage: "exclamationmark.triangle")
            } else if let entry = scheduler.scheduledPlan(for: planned) {
                if entry.isComplete {
                    Label("Odrađeno na satu. Trening se upisuje u povijest kad stigne iz Zdravlja.", systemImage: "checkmark.circle")
                } else {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zakazano na satu")
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "applewatch")
                    }
                    Text("Pokreni na satu u aplikaciji Workout, pod nazivom „\(planned.template.name)”.")
                }
            } else {
                Text("Plan još nije na satu.")
                Button("Zakaži na satu", systemImage: "applewatch.and.arrow.forward") { schedule() }
                    .disabled(isScheduling)
                if failed {
                    Text("Zakazivanje nije uspjelo. Provjeri je li sat uparen i je li Apollu dopušteno zakazivanje treninga.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            Text("Trening se pokreće na satu u aplikaciji Workout. Kad ga završiš, Apolon ga uvozi iz Zdravlja i raspored ide dalje.")
        }
        .task { CardioWorkoutScheduler.shared.refresh(context: context) }
    }

    private func schedule() {
        isScheduling = true
        Task {
            failed = !(await CardioWorkoutScheduler.shared.scheduleNow(planned))
            isScheduling = false
        }
    }
}
