import AudioToolbox
import Catalog
import Models
import SwiftData
import SwiftUI
import Training
import Units

/// Ekran aktivnog treninga (specifikacija, odjeljak 2): popis vježbi s jednom otvorenom, kvačica na seriji,
/// rest timer pri dnu, superset, uklanjanje s poništavanjem i promjena redoslijeda povlačenjem.
struct ActiveWorkoutScreen: View {
    let session: Session

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var settings: UserSettings?
    @State private var previousSets: [UUID: [SetValues]] = [:]
    @State private var openExerciseID: UUID?
    @State private var editMode: EditMode = .inactive

    @State private var showsPicker = false
    @State private var supersetSource: SessionExercise?
    @State private var showsRemoved = false
    @State private var showsFinishPrompt = false
    @State private var showsFinishConfirmation = false
    @State private var showsDiscardConfirmation = false
    @State private var showsNothingCompleted = false
    @State private var finishedSummary: WorkoutSummary?
    @State private var lastRemoved: SessionExercise?
    @State private var errorText: String?
    @State private var completedCount = 0
    @State private var errorCount = 0

    private var engine: WorkoutEngine { WorkoutEngine(context: context) }
    private var unit: WeightUnit { settings?.weightUnit ?? .kilograms }
    private var visible: [SessionExercise] { session.orderedExercises.filter { !$0.isRemoved } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { exercise in
                    card(for: exercise)
                }
                .onMove { source, destination in
                    try? engine.moveExercises(in: session, from: source, to: destination)
                }

                Section {
                    Button("Dodaj vježbu", systemImage: "plus") { showsPicker = true }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBars }
            .sensoryFeedback(.success, trigger: completedCount)
            .sensoryFeedback(.error, trigger: errorCount)
            .onChange(of: session.restTimerEndsAt) { _, endsAt in
                RestNotifications.sync(endsAt: endsAt, soundEnabled: settings?.restEndSoundEnabled ?? true)
            }
            .sheet(item: Binding(
                get: { finishedSummary.map(SummaryBox.init) },
                set: { if $0 == nil { finishedSummary = nil } }
            )) { box in
                WorkoutSummarySheet(session: session, summary: box.summary, unit: unit) {
                    finishedSummary = nil
                    dismiss()
                }
            }
            .sheet(isPresented: $showsPicker) {
                ExercisePickerSheet(title: "Dodaj vježbu") { summary, inputType in
                    add(summary, inputType: inputType)
                }
            }
            .sheet(item: $supersetSource) { source in
                SupersetPartnerSheet(
                    source: source,
                    // Za partnera se nude samo vježbe koje još nisu u supersetu.
                    candidates: visible.filter { $0.id != source.id && $0.supersetGroupId == nil }
                ) { partner in
                    let members = engine.group(of: source) + [partner]
                    try? engine.makeSuperset(members, in: session)
                }
            }
            .sheet(isPresented: $showsRemoved) {
                RemovedExercisesSheet(exercises: engine.removedExercises(in: session)) { exercise in
                    try? engine.restoreExercise(exercise)
                }
            }
            .confirmationDialog("Sve serije su završene", isPresented: $showsFinishPrompt, titleVisibility: .visible) {
                Button("Završi trening") { finish() }
                Button("Dodaj vježbu") { showsPicker = true }
                Button("Nastavi", role: .cancel) {}
            }
            .confirmationDialog("Završiti trening?", isPresented: $showsFinishConfirmation, titleVisibility: .visible) {
                Button("Završi trening") { finish() }
                Button("Nastavi", role: .cancel) {}
            } message: {
                Text("Serije koje nisu označene završenima neće se spremiti.")
            }
            .confirmationDialog("Odbaciti trening?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Odbaci trening", role: .destructive) { discard() }
                Button("Nastavi", role: .cancel) {}
            } message: {
                Text("Trening i sve unesene serije bit će obrisani.")
            }
            .alert("Nema završenih serija", isPresented: $showsNothingCompleted) {
                Button("Odbaci trening", role: .destructive) { discard() }
                Button("Nastavi", role: .cancel) {}
            } message: {
                Text("Trening bez ijedne završene serije ne može se spremiti.")
            }
            .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("U redu") {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .task {
            settings = try? GymQueries(context: context).settings()
            reloadPrevious()
            if openExerciseID == nil {
                openExerciseID = visible.first { $0.orderedSets.contains { !$0.isCompleted } }?.id ?? visible.first?.id
            }
            // Timer koji je istekao dok je aplikacija bila ugašena ne prikazuje se.
            if let timer = engine.restTimer(of: session), timer.isExpired(at: Date()) {
                try? engine.cancelRest(of: session)
            }
        }
    }

    // MARK: Dijelovi ekrana

    private func card(for exercise: SessionExercise) -> some View {
        ExerciseCard(
            exercise: exercise,
            isOpen: isOpen(exercise),
            isEditing: editMode.isEditing,
            highlightedSetID: highlightedSetID(for: exercise),
            previous: previousSets[exercise.id] ?? [],
            unit: unit,
            effortScale: settings?.effortScale ?? .rpe,
            onToggleOpen: { openExerciseID = isOpen(exercise) ? nil : exercise.id },
            onEdit: { try? engine.touch(session) },
            onToggleComplete: { toggleComplete($0, in: exercise) },
            onChangeKind: { set, kind in
                set.kind = kind
                try? engine.touch(session)
            },
            onDeleteSet: { try? engine.removeSet($0) },
            onAddSet: { kind in _ = try? engine.addSet(to: exercise, kind: kind) },
            onRemove: { remove(exercise) },
            onSuperset: { supersetSource = exercise },
            onLeaveSuperset: { try? engine.removeFromSuperset(exercise) }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Smanji", systemImage: "chevron.down") { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            Text(session.startedAt, style: .timer)
                .font(.headline.monospacedDigit())
                .accessibilityLabel(Text("Trajanje treninga"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Više", systemImage: "ellipsis.circle") {
                Button(editMode.isEditing ? "Gotovo s redoslijedom" : "Promijeni redoslijed", systemImage: "arrow.up.arrow.down") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                Button("Uklonjene vježbe (\(engine.removedExercises(in: session).count))", systemImage: "arrow.uturn.backward") {
                    showsRemoved = true
                }
                .disabled(engine.removedExercises(in: session).isEmpty)
                Button("Odbaci trening", systemImage: "trash", role: .destructive) { showsDiscardConfirmation = true }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Završi") { showsFinishConfirmation = true }
        }
    }

    @ViewBuilder
    private var bottomBars: some View {
        VStack(spacing: 8) {
            if let removed = lastRemoved {
                HStack {
                    Text("Vježba uklonjena")
                    Spacer()
                    Button("Poništi") {
                        try? engine.restoreExercise(removed)
                        openExerciseID = removed.id
                        lastRemoved = nil
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .padding(.horizontal)
                .task(id: removed.id) {
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { lastRemoved = nil }
                }
            }
            if let timer = engine.restTimer(of: session) {
                RestTimerBar(
                    timer: timer,
                    onAdjust: { try? engine.adjustRest(of: session, bySeconds: $0) },
                    onSkip: { try? engine.cancelRest(of: session) },
                    onExpire: restExpired
                )
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Ponašanje

    private func isOpen(_ exercise: SessionExercise) -> Bool {
        if exercise.id == openExerciseID { return true }
        // Superset se otvara u cjelini.
        guard let group = exercise.supersetGroupId else { return false }
        return visible.first { $0.id == openExerciseID }?.supersetGroupId == group
    }

    /// Sljedeća serija za unos: prva nezavršena, a u supersetu po naizmjeničnom redoslijedu.
    private func highlightedSetID(for exercise: SessionExercise) -> UUID? {
        let members = engine.group(of: exercise)
        guard members.count > 1 else {
            return exercise.orderedSets.first { !$0.isCompleted }?.id
        }
        let next = SupersetSequence.nextIncomplete(setCounts: members.map { $0.orderedSets.count }) { position in
            members[position.exercise].orderedSets[position.set].isCompleted
        }
        return next.map { members[$0.exercise].orderedSets[$0.set].id }
    }

    private func toggleComplete(_ set: SetLog, in exercise: SessionExercise) {
        do {
            if set.isCompleted {
                try engine.uncompleteSet(set)
                return
            }
            try engine.completeSet(set, defaultRestSeconds: settings?.defaultRestSeconds ?? 90)
            completedCount += 1
            advance(after: exercise)
        } catch WorkoutError.setIncomplete {
            errorCount += 1
            errorText = String(localized: "Upiši sve vrijednosti serije prije označavanja.")
        } catch {
            errorText = String(localized: "Serija se nije mogla spremiti.")
        }
    }

    /// Kad je vježba (ili superset) gotova, otvara se prva nekompletirana vježba, a kad je sve gotovo nudi se završetak.
    private func advance(after exercise: SessionExercise) {
        let groupDone = engine.group(of: exercise).allSatisfy { $0.orderedSets.allSatisfy(\.isCompleted) }
        guard groupDone else { return }
        let flags = visible.map { $0.orderedSets.allSatisfy(\.isCompleted) }
        if let index = WorkoutFlow.firstIncompleteExercise(isFullyCompleted: flags) {
            openExerciseID = visible[index].id
        } else {
            showsFinishPrompt = true
        }
    }

    private func add(_ summary: ExerciseSummary, inputType: ExerciseInputType) {
        if let exercise = try? engine.addExercise(summary.ref, inputType: inputType, to: session) {
            openExerciseID = exercise.id
            reloadPrevious()
        }
    }

    private func remove(_ exercise: SessionExercise) {
        try? engine.removeExercise(exercise)
        lastRemoved = exercise
        if openExerciseID == exercise.id {
            openExerciseID = visible.first { $0.orderedSets.contains { !$0.isCompleted } }?.id
        }
    }

    private func restExpired() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if settings?.restEndSoundEnabled ?? true {
            AudioServicesPlaySystemSound(1007)
        }
        try? engine.cancelRest(of: session)
    }

    private func finish() {
        do {
            try engine.finishSession(session)
            RestNotifications.cancel()
            let tracked = PRKind.kinds(fromSettings: settings?.trackedPRKinds ?? [])
            finishedSummary = try engine.summary(of: session, trackedKinds: tracked)
        } catch WorkoutError.nothingCompleted {
            showsNothingCompleted = true
        } catch {
            errorText = String(localized: "Trening se nije mogao spremiti.")
        }
    }

    private func discard() {
        RestNotifications.cancel()
        try? engine.discardSession(session)
        dismiss()
    }

    /// Serije zadnjeg izvođenja svake vježbe: prethodne vrijednosti u retku i izvor smart defaultsa.
    private func reloadPrevious() {
        let queries = GymQueries(context: context)
        for exercise in session.orderedExercises where previousSets[exercise.id] == nil {
            let last = try? queries.lastPerformance(of: exercise.exercise)
            previousSets[exercise.id] = last?.orderedSets.filter(\.isCompleted).map(\.values) ?? []
        }
    }
}

private struct SupersetPartnerSheet: View {
    let source: SessionExercise
    let candidates: [SessionExercise]
    let onPick: (SessionExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button(candidate.exerciseName) {
                    onPick(candidate)
                    dismiss()
                }
                .foregroundStyle(.primary)
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Nema druge vježbe",
                        systemImage: "rectangle.stack",
                        description: Text("Prvo dodaj vježbu s kojom ćeš je spojiti u superset.")
                    )
                }
            }
            .navigationTitle("Superset s")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Odustani") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct RemovedExercisesSheet: View {
    let exercises: [SessionExercise]
    let onRestore: (SessionExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(exercises) { exercise in
                HStack {
                    VStack(alignment: .leading) {
                        Text(exercise.exerciseName)
                        Text("\(exercise.orderedSets.filter(\.isCompleted).count) završenih serija")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Vrati") {
                        onRestore(exercise)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Uklonjene vježbe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Gotovo") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Omot da se sažetak može koristiti kao `item` lista.
private struct SummaryBox: Identifiable, Equatable {
    let id = UUID()
    let summary: WorkoutSummary
}
