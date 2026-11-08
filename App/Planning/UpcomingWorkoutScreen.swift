import Catalog
import Models
import Planning
import SwiftData
import SwiftUI

/// Sljedeći trening rasporeda s privremenim izmjenama samo za ovaj ciklus:
/// preskoči trening, izbaci vježbu ili zamijeni vježbu. Izmjene se mogu poništiti dok trening nije završen.
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

    /// Sljedeći trening s izmjenama ciklusa. Čitanje `overrides` veže zaslon na izmjene, pa se osvježi kad se
    /// promijene. Nekad je to radio `.id(overrides.count)`, ali on je gradio cijeli zaslon iznova, zajedno
    /// s otvorenim listom i treningom.
    private var nextWorkout: PlannedWorkout? {
        _ = overrides.count
        return try? engine.nextWorkout(of: schedule)
    }

    var body: some View {
        List {
            if let planned = nextWorkout {
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
        .errorAlert($errorText)
    }

    @ViewBuilder
    private func content(for planned: PlannedWorkout) -> some View {
        Section {
            Text(planned.template.name).font(.itemTitle)
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
                        .tint(.red)
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
            .filter { $0.scheduleItemId == planned.item.id && ($0.kind == .removeExercise || $0.kind == .replaceExercise) }
    }

    private func label(of change: CycleOverride, in planned: PlannedWorkout) -> String {
        let original = planned.template.orderedExercises.first { $0.exercise.key == change.targetExerciseKey }?.exerciseName ?? ""
        switch change.kind {
        case .removeExercise: return String(localized: "Izbačeno: \(original)")
        case .replaceExercise: return String(localized: "\(original) → \(change.replacementName ?? "")")
        case .skipWorkout, .completedWorkout: return ""
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
            if let presentedSession { PhoneWatchSync.shared.sessionStarted(presentedSession) }
        } catch {
            errorText = String(localized: "Trening se nije mogao pokrenuti.")
        }
    }
}

/// Sljedeći trening u listu (dodir na podsjetnik), s gumbom Gotovo.
struct UpcomingWorkoutSheet: View {
    let schedule: Schedule
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            UpcomingWorkoutScreen(schedule: schedule)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Gotovo", action: onDone)
                    }
                }
        }
    }
}
