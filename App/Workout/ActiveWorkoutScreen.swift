import AudioToolbox
import Catalog
import Models
import Planning
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Ekran aktivnog treninga (specifikacija, odjeljak 2): popis vježbi s jednom otvorenom, kvačica na seriji,
/// rest timer pri dnu, superset, uklanjanje vježbe i brisanje serije s poništavanjem te promjena redoslijeda povlačenjem.
struct ActiveWorkoutScreen: View {
    let session: Session

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CatalogStore.self) private var catalogStore

    // Postavke iz upita, a ne zapamćeni objekt: nakon sinkronizacije duplikat postavki može biti obrisan.
    @Query private var settingsList: [UserSettings]
    /// Za fotografije vlastitih vježbi u sličicama.
    @Query private var customExercises: [CustomExercise]
    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }
    @State private var previousSets: [UUID: [SetValues]] = [:]
    @State private var openExerciseID: UUID?
    @State private var editMode: EditMode = .inactive

    @State private var showsPicker = false
    @State private var supersetSource: SessionExercise?
    /// Vježba čije se upute (animacija i opis) prikazuju u listu.
    @State private var infoExercise: SessionExercise?
    @State private var showsRemoved = false
    @State private var showsFinishPrompt = false
    @State private var showsFinishConfirmation = false
    @State private var showsDiscardConfirmation = false
    @State private var showsNothingCompleted = false
    /// Sažetak se spremi jednom: id lista mora ostati isti dok je otvoren, inače se list zatvori i otvori
    /// iznova i izgubi upisanu bilješku.
    @State private var finishedSummary: SummaryBox?
    /// Zadnja radnja koja se može poništiti: izbačena vježba ili obrisana serija.
    @State private var lastUndo: UndoAction?
    @State private var errorText: String?
    @State private var completedCount = 0
    /// Broj završenih serija koje je ekran već vidio. Serija potvrđena izvan ekrana (Live Activity, sat)
    /// poveća stvarni broj, pa ekran prijeđe na sljedeću vježbu kao da je kvačica pritisnuta ovdje.
    @State private var seenCompletedSets: Int?
    @State private var errorCount = 0
    /// Trening se zatvara s ovog ekrana (a ne sa sata).
    @State private var isClosingHere = false
    /// Odgođeno spremanje izmjene polja serije (`scheduleSave`).
    @State private var pendingSave: Task<Void, Never>?
    /// Vježba koja se mijenja drugom (zauzeta sprava).
    @State private var replaceSource: SessionExercise?
    /// Vježba čija se trajna bilješka uređuje.
    @State private var noteExercise: SessionExercise?
    /// Ključevi nedavnih vježbi za odabir (`GymQueries.recentExerciseKeys`).
    @State private var recentKeys: [String] = []
    /// Ranija izvođenja svake vježbe za oznaku rekorda u retku serije.
    @State private var recordHistories: [UUID: RecordHistory] = [:]

    private var engine: WorkoutEngine { WorkoutEngine(context: context) }
    private var unit: WeightUnit { settings?.weightUnit ?? .kilograms }
    private var visible: [SessionExercise] { session.orderedExercises.filter { !$0.isRemoved } }
    /// Trening vodi sat: ovdje se zrcali, a izmjene idu na sat.
    private var isLedByWatch: Bool { session.controllingDevice == .watch }
    private var completedSetCount: Int { visible.reduce(0) { $0 + $1.orderedSets.filter(\.isCompleted).count } }

    var body: some View {
        NavigationStack {
            // Korak težine vježbe na kotačiću (oprema ili vlastiti korak, `WeightStepSettings`): jedan za sve kartice.
            let weightStep = WeightStepSettings.resolver(settings: settings, catalog: catalogStore.catalog, custom: customExercises)
            List {
                if isLedByWatch {
                    Label("Trening vodi Apple Watch", systemImage: "applewatch")
                        .foregroundStyle(.secondary)
                }
                if editMode.isEditing {
                    // Kod promjene redoslijeda vježbe su zatvorene, jedna vježba je jedan redak.
                    ForEach(visible) { exercise in
                        card(for: exercise, weightStep: weightStep)
                    }
                    .onMove { source, destination in
                        try? engine.moveExercises(in: session, from: source, to: destination)
                    }
                } else {
                    // Svaka vježba je svoja sekcija, a serija svoj redak koji se briše povlačenjem.
                    ForEach(visible) { exercise in
                        Section { card(for: exercise, weightStep: weightStep) }
                    }
                }

                Section {
                    Button("Dodaj vježbu", systemImage: "plus") { showsPicker = true }
                }
            }
            // Manji razmak među vježbama, kao među karticama na početnom ekranu.
            .listSectionSpacing(16)
            // Retci zaglavlja tablice i gumba niži su od zadane najmanje visine retka.
            .environment(\.defaultMinListRowHeight, 32)
            .environment(\.editMode, $editMode)
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBars }
            .sensoryFeedback(.success, trigger: completedCount)
            .sensoryFeedback(.error, trigger: errorCount)
            .onChange(of: session.restTimerEndsAt) {
                // Obavijest o kraju odmora premješta se s timerom (+10 / −10, preskakanje).
                WorkoutLiveUpdates.shared.refresh()
            }
            .onChange(of: session.lastActivityAt) {
                if session.state == .active { PhoneWatchSync.shared.sessionChanged(session) }
                WorkoutLiveUpdates.shared.refresh()
            }
            .onChange(of: completedSetCount) { syncCompletedSets() }
            .onChange(of: scenePhase) { _, phase in
                // Promjena iz Live Activityja dok je aplikacija u pozadini provjerava se i pri povratku.
                if phase == .active { syncCompletedSets() } else { flushPendingSave() }
            }
            .onChange(of: session.stateRaw) {
                // Trening je završen ili odbačen na satu: ekran se zatvara.
                if session.state != .active, !isClosingHere { dismiss() }
            }
            .sheet(item: $finishedSummary) { box in
                WorkoutSummarySheet(session: session, summary: box.summary, unit: unit) {
                    finishedSummary = nil
                    dismiss()
                }
            }
            .sheet(isPresented: $showsPicker) {
                ExercisePickerSheet(
                    title: "Dodaj vježbu", allowsMultiple: true, recentKeys: recentKeys,
                    excludedKeys: Set(visible.map(\.exerciseKey))
                ) { summary, inputType in
                    add(summary, inputType: inputType)
                }
            }
            .background { exerciseSheets }
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
            .sheet(item: $infoExercise) { exercise in
                if let source = exercise.exercise.source {
                    ExerciseInfoSheet(source: source)
                }
            }
            .sheet(isPresented: $showsRemoved) {
                RemovedExercisesSheet(exercises: engine.removedExercises(in: session)) { exercise in
                    try? engine.restoreExercise(exercise)
                }
            }
            .alert("Sve serije su završene", isPresented: $showsFinishPrompt) {
                Button("Završi trening") { finish() }
                Button("Dodaj vježbu") { showsPicker = true }
                Button("Nastavi", role: .cancel) {}
            }
            .alert("Završiti trening?", isPresented: $showsFinishConfirmation) {
                Button("Završi trening") { finish() }
                Button("Nastavi", role: .cancel) {}
            } message: {
                Text("Serije koje nisu označene završenima neće se spremiti.")
            }
            .alert("Odbaciti trening?", isPresented: $showsDiscardConfirmation) {
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
            .errorAlert($errorText)
        }
        .onAppear { WorkoutScreenPresence.appeared() }
        .onDisappear {
            flushPendingSave()
            WorkoutScreenPresence.disappeared()
        }
        .task {
            // Trening je u međuvremenu završen (npr. na satu): nema se što nastaviti.
            if session.state != .active {
                dismiss()
                return
            }
            _ = try? GymQueries(context: context).settings()
            if session.state == .active { PhoneWatchSync.shared.sessionChanged(session) }
            PerformanceSignpost.measure("WorkoutOpen") { reloadPrevious() }
            recentKeys = (try? GymQueries(context: context).recentExerciseKeys()) ?? []
            if openExerciseID == nil {
                openExerciseID = visible.first { $0.orderedSets.contains { !$0.isCompleted } }?.id ?? visible.first?.id
            }
            if seenCompletedSets == nil { seenCompletedSets = completedSetCount }
            // Timer koji je istekao dok je aplikacija bila ugašena ne prikazuje se (trening na satu čisti sat).
            if !isLedByWatch, let timer = engine.restTimer(of: session), timer.isExpired(at: Date()) {
                try? engine.cancelRest(of: session)
            }
            // Live Activity se pokreće (ili osvježava) čim je trening na ekranu.
            WorkoutLiveUpdates.shared.refresh()
        }
    }

    // MARK: Dijelovi ekrana

    private func card(for exercise: SessionExercise, weightStep: (ExerciseRef) -> Double) -> some View {
        ExerciseCard(
            exercise: exercise,
            thumbnail: catalogStore.thumbnail(for: exercise.exercise.source, customExercises: customExercises),
            isOpen: isOpen(exercise),
            isEditing: editMode.isEditing,
            highlightedSetID: highlightedSetID(for: exercise),
            previous: previousSets[exercise.id] ?? [],
            unit: unit,
            effortScale: settings?.effortScale ?? .rpe,
            persistentNote: settings?.exerciseNotes.note(for: exercise.exerciseKey),
            canAddWarmUps: engine.canAddWarmUps(to: exercise),
            recordSetIDs: recordSetIDs(in: exercise),
            onToggleOpen: { openExerciseID = isOpen(exercise) ? nil : exercise.id },
            onEdit: scheduleSave,
            onToggleComplete: { toggleComplete($0, in: exercise) },
            onChangeKind: { set, kind in
                set.kind = kind
                try? engine.touch(session)
            },
            onDeleteSet: { deleteSet($0, in: exercise) },
            onAddSet: { kind in _ = try? engine.addSet(to: exercise, kind: kind) },
            onRemove: { remove(exercise) },
            onSuperset: { supersetSource = exercise },
            onLeaveSuperset: { try? engine.removeFromSuperset(exercise) },
            onReplace: { replaceSource = exercise },
            onEditNote: { noteExercise = exercise },
            onAddWarmUps: { addWarmUps(to: exercise, step: weightStep(exercise.exercise)) },
            onShowInfo: exercise.exercise.source == nil ? nil : { infoExercise = exercise }
        )
        .environment(\.weightStep, weightStep(exercise.exercise))
    }

    @ViewBuilder
    private var bottomBars: some View {
        VStack(spacing: 8) {
            if let undo = lastUndo {
                HStack {
                    Text(undo.message)
                    Spacer()
                    Button("Poništi") { self.undo(undo) }
                }
                .padding(12)
                .background(.regularMaterial, in: .rect(cornerRadius: CornerRadius.floating))
                .padding(.horizontal)
                .task(id: undo.id) {
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { lastUndo = nil }
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
                cancelPendingSave()
                return
            }
            let catalog = catalogStore.catalog
            try engine.completeSet(
                set, restDefaults: settings?.restDefaults ?? .standard,
                isCompound: { catalog?.isCompound(exerciseKey: $0) }
            )
            // `completeSet` je spremio i izmjene koje su čekale odgođeno spremanje.
            cancelPendingSave()
            completedCount += 1
            syncCompletedSets()
        } catch WorkoutError.setIncomplete {
            errorCount += 1
            errorText = String(localized: "Upiši sve vrijednosti serije prije označavanja.")
        } catch {
            errorText = String(localized: "Serija se nije mogla spremiti.")
        }
    }

    /// Nova završena serija, bilo s ovog ekrana, iz Live Activityja ili sa sata: kad je otvorena vježba
    /// (ili superset) gotova, otvara se prva nekompletirana vježba, a kad je sve gotovo nudi se završetak.
    private func syncCompletedSets() {
        let count = completedSetCount
        defer { seenCompletedSets = count }
        guard let seen = seenCompletedSets, WorkoutFlow.hasNewCompletion(completedCount: count, lastSeen: seen) else { return }
        // Sve vježbe zatvorene: gleda se vježba zadnje završene serije.
        guard let exercise = visible.first(where: { $0.id == openExerciseID }) ?? lastCompletedExercise() else { return }
        let groupDone = engine.group(of: exercise).allSatisfy { $0.orderedSets.allSatisfy(\.isCompleted) }
        let flags = visible.map { $0.orderedSets.allSatisfy(\.isCompleted) }
        switch WorkoutFlow.advance(openGroupDone: groupDone, isFullyCompleted: flags) {
        case .stay: break
        case .open(let index): openExerciseID = visible[index].id
        case .finished: showsFinishPrompt = true
        }
    }

    private func lastCompletedExercise() -> SessionExercise? {
        visible.max { lhs, rhs in
            (lhs.orderedSets.compactMap(\.completedAt).max() ?? .distantPast)
                < (rhs.orderedSets.compactMap(\.completedAt).max() ?? .distantPast)
        }
    }

    private func restExpired() {
        // Trening na satu: kraj odmora javlja sat, a sat i gasi timer.
        guard !isLedByWatch else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if settings?.restEndSoundEnabled ?? true {
            AudioServicesPlaySystemSound(1007)
        }
        try? engine.cancelRest(of: session)
    }

    private func finish() {
        isClosingHere = true
        flushPendingSave()
        do {
            try engine.finishSession(session)
            WorkoutLifecycle.finished(session, context: context, origin: .phone)
            let tracked = PRKind.tracked(by: settings)
            let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
            finishedSummary = SummaryBox(summary: try engine.summary(
                of: session, trackedKinds: tracked, excludedExercises: settings?.prExcludedExerciseKeys ?? [],
                isCompound: { info($0)?.isCompound }, isCardio: ExerciseInfoBuilder.isCardio(info)
            ))
        } catch WorkoutError.nothingCompleted {
            isClosingHere = false
            showsNothingCompleted = true
        } catch {
            isClosingHere = false
            errorText = String(localized: "Trening se nije mogao spremiti.")
        }
    }

    private func discard() {
        isClosingHere = true
        cancelPendingSave()
        WorkoutLifecycle.discard(session, context: context)
        dismiss()
    }

    /// Serije zadnjeg izvođenja svake vježbe: prethodne vrijednosti u retku i izvor smart defaultsa.
    private func reloadPrevious() {
        let queries = GymQueries(context: context)
        for exercise in session.orderedExercises where previousSets[exercise.id] == nil {
            previousSets[exercise.id] = (try? queries.previousSetValues(of: exercise.exercise, preferringTemplate: session.templateId)) ?? []
            recordHistories[exercise.id] = try? engine.recordHistory(of: exercise.exercise, before: session, inputType: exercise.inputType)
        }
    }
}

// Traka je u ekstenziji da tijelo strukture ostane u granicama SwiftLinta.
extension ActiveWorkoutScreen {
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Smanji", systemImage: "chevron.down") { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            Text(session.startedAt, style: .timer)
                // Isti broj kao u retku liste: zaobljen, semibold, veličine naslova u traci.
                .font(.rowValue)
                .accessibilityLabel(Text("Trajanje treninga"))
        }
        if editMode.isEditing {
            // Dok traje premještanje u kutu je samo kvačica koja ga završava,
            // da se "Završi" ne bi pomiješao sa završetkom premještanja.
            ToolbarItem(placement: .confirmationAction) {
                Button("Gotovo s redoslijedom", systemImage: "checkmark") {
                    withAnimation { editMode = .inactive }
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Više", systemImage: "ellipsis.circle") {
                    Button("Promijeni redoslijed", systemImage: "arrow.up.arrow.down") {
                        withAnimation { editMode = .active }
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
    }
}

/// Stranica vježbe iz kataloga (animacija, mišići, upute) ili vlastite vježbe, otvorena usred treninga.
private struct ExerciseInfoSheet: View {
    let source: ExerciseSummary.Source
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailScreen(source: source, allowsRemoving: false)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Gotovo") { dismiss() } }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
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

/// Radnja s trake "Poništi" pri dnu ekrana.
private enum UndoAction {
    case exercise(SessionExercise)
    case set(RemovedSet, exercise: SessionExercise)

    /// Nova radnja ponovno pokreće odbrojavanje trake.
    var id: UUID {
        switch self {
        case .exercise(let exercise): return exercise.id
        case .set(let removed, _): return removed.id
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .exercise: return "Vježba uklonjena"
        case .set: return "Serija obrisana"
        }
    }
}

/// Omot da se sažetak može koristiti kao `item` lista.
private struct SummaryBox: Identifiable, Equatable {
    let id = UUID()
    let summary: WorkoutSummary
}

// MARK: Vježbe: dodavanje, zamjena, bilješke i zagrijavanje

extension ActiveWorkoutScreen {
    private func add(_ summary: ExerciseSummary, inputType: ExerciseInputType) {
        if let exercise = try? engine.addExercise(summary.ref, inputType: inputType, to: session) {
            openExerciseID = exercise.id
            reloadPrevious()
        }
    }

    private func remove(_ exercise: SessionExercise) {
        try? engine.removeExercise(exercise)
        lastUndo = .exercise(exercise)
        if openExerciseID == exercise.id {
            openExerciseID = visible.first { $0.orderedSets.contains { !$0.isCompleted } }?.id
        }
    }

    private func deleteSet(_ set: SetLog, in exercise: SessionExercise) {
        guard let removed = try? engine.removeSet(set) else { return }
        lastUndo = .set(removed, exercise: exercise)
    }

    private func undo(_ action: UndoAction) {
        switch action {
        case .exercise(let exercise):
            try? engine.restoreExercise(exercise)
            openExerciseID = exercise.id
        case .set(let removed, let exercise):
            try? engine.restoreSet(removed, to: exercise)
            openExerciseID = exercise.id
        }
        lastUndo = nil
    }

    /// Listovi za zamjenu vježbe i trajnu bilješku. Na pozadini ekrana, da tijelo strukture ostane u granicama SwiftLinta.
    private var exerciseSheets: some View {
        Color.clear
            .sheet(item: $replaceSource) { source in
                ExercisePickerSheet(
                    title: "Zamijeni vježbu", suggested: alternatives(to: source), recentKeys: recentKeys,
                    excludedKeys: Set(visible.map(\.exerciseKey))
                ) { summary, inputType in
                    replace(source, with: summary, inputType: inputType)
                }
            }
            .sheet(item: $noteExercise) { exercise in
                ExerciseNoteSheet(
                    exerciseName: exercise.exerciseName,
                    initialText: settings?.exerciseNotes.note(for: exercise.exerciseKey) ?? ""
                ) { text in
                    saveNote(text, for: exercise)
                }
            }
    }

    /// Zamjene iz kataloga i vlastitih vježbi: isti glavni mišić, a prvo oprema iz profila.
    private func alternatives(to exercise: SessionExercise) -> [ExerciseSummary] {
        let all = catalogStore.summaries + customExercises.map(\.summary)
        guard let summary = all.first(where: { $0.id == exercise.exerciseKey }) else { return [] }
        let inWorkout = Set(visible.map(\.exerciseKey))
        return ExerciseSearch.alternatives(
            to: summary, in: all.filter { !inWorkout.contains($0.id) }, preferredEquipment: Set(settings?.equipment ?? [])
        )
    }

    private func replace(_ exercise: SessionExercise, with summary: ExerciseSummary, inputType: ExerciseInputType) {
        guard let created = try? engine.replaceExercise(exercise, with: summary.ref, inputType: inputType) else {
            errorText = String(localized: "Vježba se nije mogla zamijeniti.")
            return
        }
        openExerciseID = created.id
        reloadPrevious()
    }

    private func saveNote(_ text: String, for exercise: SessionExercise) {
        guard let settings = try? GymQueries(context: context).settings() else { return }
        var notes = settings.exerciseNotes
        notes.setNote(text, for: exercise.exerciseKey)
        settings.exerciseNotes = notes
        try? engine.touch(session)
    }

    /// Završene serije vježbe koje obaraju rekord, kad su rekordi uključeni i vježba nije isključena iz njih.
    private func recordSetIDs(in exercise: SessionExercise) -> Set<UUID> {
        guard let history = recordHistories[exercise.id],
              !(settings?.prExcludedExerciseKeys ?? []).contains(exercise.exerciseKey) else { return [] }
        let done = exercise.orderedSets.filter(\.isCompleted).map { (id: $0.id, values: $0.values) }
        return PersonalRecordDetector.liveRecordSets(
            done, history: history, inputType: exercise.inputType, kinds: PRKind.tracked(by: settings), date: session.startedAt
        )
    }

    private func addWarmUps(to exercise: SessionExercise, step: Double) {
        let barbell = catalogStore.catalog?.exercise(withID: exercise.exercise.catalogId ?? "")?.equipment == .barbell
        _ = try? engine.addWarmUps(
            to: exercise, barKg: barbell ? settings?.barbellWeightKg ?? 20 : nil, step: step, unit: unit
        )
    }
}

// MARK: Odgođeno spremanje

extension ActiveWorkoutScreen {
    /// Izmjena polja serije: sprema se pola sekunde nakon zadnje izmjene, pa tipkanje ne sprema bazu na svaki znak.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            pendingSave = nil
            try? engine.touch(session)
        }
    }

    private func cancelPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
    }

    /// Izmjena koja još čeka spremanje sprema se odmah (izlazak s ekrana, završetak treninga).
    private func flushPendingSave() {
        guard let task = pendingSave else { return }
        task.cancel()
        pendingSave = nil
        try? engine.touch(session)
    }
}
