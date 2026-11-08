import Models
import Planning
import SwiftData
import SwiftUI
import Training
import Units

/// Početna: kartica za početak ili nastavak treninga i kartice koje korisnik složi.
/// Naslov je kratak (ispod 15 znakova) i nije naziv aplikacije, prema HIG-u.
struct HomeScreen: View {
    /// Zahtjev iz tipkovničkog prečaca: pokretanje treninga ili Postavke.
    @Binding var request: HomeRequest?

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Session> { $0.stateRaw == "active" }, sort: \Session.startedAt, order: .reverse)
    private var activeSessions: [Session]

    /// Za karticu zadnjeg treninga treba samo najnoviji trening i najnoviji trening iz Zdravlja, ne cijela povijest.
    @Query(HomeScreen.latestFinished) private var finishedSessions: [Session]
    @Query(HomeScreen.latestHealthWorkout) private var healthWorkouts: [HealthWorkout]
    @Query(sort: \DashboardCard.orderIndex) private var dashboardCards: [DashboardCard]
    @Query private var settingsList: [UserSettings]
    @Query private var schedules: [Schedule]
    @Query private var cycleOverrides: [CycleOverride]
    @Query private var templates: [WorkoutTemplate]
    @State private var showsSettings = false
    @State private var showsCardEditor = false
    @Namespace private var workoutTransition
    @State private var presentedSession: Session?
    /// Izbor treninga: bez rasporeda spremljeni treninzi, ispod rasporeda njegovi treninzi i ostali spremljeni.
    @State private var showsTemplatePicker = false
    /// Raspored iz kojeg je izbor otvoren (nil: izbor bez rasporeda).
    @State private var pickerSchedule: Schedule?
    /// Trening odabran u listu; pokreće se tek kad se list zatvori, jer se puni ekran ne može prikazati dok se list zatvara.
    @State private var chosenWorkout: WorkoutChoice?
    @State private var errorText: String?
    @State private var checkedRecovery = false
    /// Prazna Početna je jednom dobila karticu zadnjeg treninga.
    @AppStorage("dashboard.lastWorkoutSeeded") private var lastWorkoutSeeded = false
    @State private var recovery: RecoveryPrompt?
    #if DEBUG
    @State private var showsPrototypes = false
    #endif

    private static var latestFinished: FetchDescriptor<Session> {
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == "finished" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private static var latestHealthWorkout: FetchDescriptor<HealthWorkout> {
        var descriptor = FetchDescriptor<HealthWorkout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        // Sljedeći treninzi se računaju jednom po iscrtavanju (dohvat rasporeda i izmjena ciklusa).
        let upcoming = upcomingWorkouts
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    startSection(upcoming)
                    ForEach(visibleCards) { card in
                        if let kind = card.kind {
                            cardView(kind, upcoming: upcoming)
                        }
                    }
                    Button("Uredi kartice", systemImage: "square.grid.2x2") { showsCardEditor = true }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Početna")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Postavke", systemImage: "gearshape") {
                        showsSettings = true
                    }
                }
                #if DEBUG
                if !ScreenshotMode.isActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Prototipi", systemImage: "hammer") {
                            showsPrototypes = true
                        }
                    }
                }
                #endif
            }
            .sheet(isPresented: $showsSettings) {
                SettingsScreen()
            }
            .sheet(isPresented: $showsTemplatePicker, onDismiss: startChosenWorkout) {
                templatePicker(upcoming)
            }
            .sheet(isPresented: $showsCardEditor) {
                DashboardEditor()
            }
            .fullScreenCover(item: $presentedSession) { session in
                ActiveWorkoutScreen(session: session)
                    // Zoom prijelaz iz kartice: povlačenje ekrana prema dolje sažima trening natrag u karticu.
                    .navigationTransition(.zoom(sourceID: Self.workoutTransitionID, in: workoutTransition))
            }
            .task {
                checkRecovery()
            }
            // Uz sinkronizaciju se čeka prvi uvoz s iClouda: na novom uređaju kartice tek stižu s drugih uređaja.
            .task(id: SyncMonitor.shared.tracker.lastImport) {
                seedLastWorkoutCard()
            }
            // `initial`: pri hladnom pokretanju iz Live Activityja zahtjev stigne prije nego što se Početna prikaže.
            .onChange(of: request, initial: true) { _, newValue in
                guard let newValue else { return }
                request = nil
                handle(newValue)
            }
            .confirmationDialog(
                recovery?.isStale == true ? Text("Zaboravljen trening") : Text("Prekinut trening"),
                isPresented: Binding(get: { recovery != nil }, set: { if !$0 { recovery = nil } }),
                titleVisibility: .visible,
                presenting: recovery
            ) { prompt in
                Button("Nastavi trening") { presentedSession = prompt.session }
                Button("Završi i spremi") { closeStale(prompt.session) }
                Button("Odbaci trening", role: .destructive) { discard(prompt.session) }
            } message: { prompt in
                if prompt.isStale {
                    Text("Trening je otvoren dulje od 6 sati bez aktivnosti. Završi ga na zadnjoj završenoj seriji ili ga odbaci.")
                } else {
                    Text("Trening je ostao otvoren. Možeš ga nastaviti, završiti ili odbaciti.")
                }
            }
            .errorAlert($errorText)
            #if DEBUG
            .sheet(isPresented: $showsPrototypes) {
                PrototypesView()
            }
            #endif
        }
    }

    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }
    private var lastSession: Session? {
        Session.merged(finishedSessions, health: healthWorkouts).first
    }

    private var visibleCards: [DashboardCard] {
        _ = dashboardCards.map(\.orderIndex)
        return (try? DashboardLayout(context: context).cards()) ?? []
    }

    @ViewBuilder
    private func cardView(_ kind: DashboardCardKind, upcoming: [PlannedWorkout]) -> some View {
        switch kind {
        case .lastWorkout:
            if let last = lastSession {
                LastWorkoutCard(session: last, unit: unit)
            }
        case .plateCalculator: PlateCalculatorCard(unit: unit)
        case .nextWorkout: NextWorkoutCard(planned: upcoming)
        case .weeklyVolume: WeeklyVolumeCard(unit: unit)
        }
    }

    /// Kartica na vrhu: trening u tijeku sažet u karticu (kao Live Activity) ili početak novog (iz rasporeda ili praznog).
    /// Ista je izvor zoom prijelaza, pa se ekran treninga otvara iz nje i povlačenjem dolje sažima natrag u nju.
    private func startSection(_ upcoming: [PlannedWorkout]) -> some View {
        Group {
            if let active = activeSessions.first {
                ActiveWorkoutCard(session: active, unit: unit) { presentedSession = active }
            } else {
                StartWorkoutCard(
                    planned: upcoming,
                    templateCount: startableTemplates.count,
                    onStart: { planned in start(planned) },
                    offersOtherWorkout: { offersOtherWorkout($0) },
                    onChooseTemplate: { schedule in
                        pickerSchedule = schedule
                        showsTemplatePicker = true
                    },
                    onStartEmpty: startWorkout
                )
            }
        }
        .matchedTransitionSource(id: Self.workoutTransitionID, in: workoutTransition) { source in
            source.clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
        }
    }

    private static let workoutTransitionID = "workout"

    /// ⌘N nastavlja trening u tijeku ili pokreće sljedeći iz rasporeda, isto kao prvi gumb na Početnoj. Bez rasporeda
    /// otvara izbor spremljenog treninga, a bez spremljenih treninga prazan trening.
    private func handle(_ request: HomeRequest) {
        guard presentedSession == nil else { return }
        switch request {
        case .activeWorkout:
            // Iz Live Activityja: zatvara se ono što je otvoreno preko Početne i otvara puni ekran treninga.
            guard let active = activeSessions.first else { return }
            let hadSheet = showsSettings || showsCardEditor || showsTemplatePicker
            showsSettings = false
            showsCardEditor = false
            showsTemplatePicker = false
            chosenWorkout = nil
            recovery = nil
            if hadSheet {
                // Puni ekran se ne može prikazati dok se list još zatvara.
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    presentedSession = active
                }
            } else {
                presentedSession = active
            }
        case .settings:
            showsSettings = true
        case .startWorkout:
            if let active = activeSessions.first {
                presentedSession = active
            } else if let planned = upcomingWorkouts.first {
                start(planned)
            } else if !startableTemplates.isEmpty {
                pickerSchedule = nil
                showsTemplatePicker = true
            } else {
                startWorkout()
            }
        }
    }

    /// Prazna Početna dobiva karticu zadnjeg treninga (jednom po uređaju).
    private func seedLastWorkoutCard() {
        guard !lastWorkoutSeeded else { return }
        if AppServices.isSyncRunning && SyncMonitor.shared.tracker.lastImport == nil { return }
        do {
            try DashboardLayout(context: context).seedLastWorkout()
            lastWorkoutSeeded = true
        } catch {
            // Pokušava se opet pri sljedećem otvaranju Početne.
        }
    }

    /// Pri pokretanju aplikacije: ako je trening ostao otvoren, nudi nastavak, spremanje ili odbacivanje.
    private func checkRecovery() {
        guard !checkedRecovery else { return }
        checkedRecovery = true
        // Trening koji vodi sat nije prekinut na iPhoneu: sat je izvor istine i javlja njegov kraj.
        guard let active = activeSessions.first, presentedSession == nil, active.controllingDevice == .phone else { return }
        let engine = WorkoutEngine(context: context)
        let assessment = RecoveryAssessment.assess(
            startedAt: active.startedAt, lastActivityAt: active.lastActivityAt,
            lastCompletedSetAt: engine.lastCompletedSetAt(in: active), now: Date()
        )
        recovery = RecoveryPrompt(session: active, isStale: assessment.isStale)
    }

    private func closeStale(_ session: Session) {
        do {
            try WorkoutEngine(context: context).closeStaleSession(session)
            PhoneWatchSync.shared.sessionChanged(session)
            WorkoutLiveUpdates.shared.refresh()
            Task { await HealthService.shared.saveWorkout(of: session, context: context) }
        } catch WorkoutError.nothingCompleted {
            // Bez završene serije nema što spremiti: trening se odbacuje.
            discard(session)
        } catch {
            errorText = String(localized: "Trening se nije mogao spremiti.")
        }
    }

    private func discard(_ session: Session) {
        PhoneWatchSync.shared.willDiscard(session)
        try? WorkoutEngine(context: context).discardSession(session)
        WorkoutLiveUpdates.shared.refresh()
        ReminderScheduler.refresh(context: context)
    }

    /// Sljedeći trening svakog aktivnog rasporeda. `schedules` i `cycleOverrides` su ovdje samo da se
    /// zaslon osvježi kad se napredovanje ili izmjene promijene.
    private var upcomingWorkouts: [PlannedWorkout] {
        _ = (schedules.count, cycleOverrides.count)
        return (try? ScheduleEngine(context: context).upcomingWorkouts()) ?? []
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

    /// Spremljeni treninzi koji se mogu pokrenuti bez rasporeda.
    private var startableTemplates: [WorkoutTemplate] {
        TemplateStarter.startable(templates)
    }

    /// List za izbor treninga: uz raspored njegovi treninzi (sljedeći označen) i ostali spremljeni, inače samo spremljeni.
    private func templatePicker(_ upcoming: [PlannedWorkout]) -> TemplatePickerSheet {
        var scheduled: [PlannedWorkout] = []
        var nextItemID: UUID?
        if let schedule = pickerSchedule {
            scheduled = workoutChoices(schedule)
            nextItemID = upcoming.first(where: { $0.schedule.id == schedule.id })?.item.id
        }
        return TemplatePickerSheet(
            schedule: pickerSchedule,
            scheduled: scheduled,
            nextItemID: nextItemID,
            templates: startableTemplates,
            onSelect: { choice in chosenWorkout = choice }
        )
    }

    /// Treninzi rasporeda za izbor umjesto sljedećeg.
    private func workoutChoices(_ schedule: Schedule) -> [PlannedWorkout] {
        (try? ScheduleEngine(context: context).workoutChoices(of: schedule)) ?? []
    }

    /// Red "Odaberi drugi trening" ispod rasporeda: ima smisla kad postoji barem jedan trening snage osim sljedećeg.
    private func offersOtherWorkout(_ planned: PlannedWorkout) -> Bool {
        startableTemplates.contains { $0.id != planned.template.id }
    }

    private func startChosenWorkout() {
        guard let choice = chosenWorkout else { return }
        chosenWorkout = nil
        do {
            presentedSession = try PerformanceSignpost.measure("WorkoutStart") { try startSession(choice) }
            ReminderScheduler.refresh(context: context)
            if let presentedSession { PhoneWatchSync.shared.sessionStarted(presentedSession) }
        } catch {
            errorText = String(localized: "Trening se nije mogao pokrenuti.")
        }
    }

    private func startSession(_ choice: WorkoutChoice) throws -> Session {
        let starter = TemplateStarter(context: context)
        switch choice {
        case .planned(let planned): return try starter.start(planned)
        case .template(let template): return try starter.start(template)
        }
    }

    private func startWorkout() {
        do {
            presentedSession = try WorkoutEngine(context: context).startSession(name: String(localized: "Trening"))
            ReminderScheduler.refresh(context: context)
            if let presentedSession { PhoneWatchSync.shared.sessionStarted(presentedSession) }
        } catch {
            errorText = String(localized: "Trening se nije mogao pokrenuti.")
        }
    }
}

private struct RecoveryPrompt: Identifiable {
    let session: Session
    let isStale: Bool
    var id: UUID { session.id }
}
