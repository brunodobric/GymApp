import Models
import Planning
import SwiftData
import SwiftUI
import Training
import Units

/// Početna: kartica za početak ili nastavak treninga i kartice koje korisnik složi.
/// Naslov je kratak (ispod 15 znakova) i nije naziv aplikacije, prema HIG-u.
struct HomeScreen: View {
    /// Mijenja se kad korisnik ponovno dodirne već otvoren tab: stog navigacije se vraća na korijen.
    var rootReset = 0

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
    /// Izbor treninga: bez rasporeda spremljeni treninzi, s rasporedima njihovi treninzi i ostali spremljeni.
    @State private var showsTemplatePicker = false
    /// Aktivni rasporedi čiji su treninzi u izboru (prazno: izbor bez rasporeda).
    @State private var pickerSchedules: [Schedule] = []
    /// Trening odabran u listu; pokreće se tek kad se list zatvori, jer se puni ekran ne može prikazati dok se list zatvara.
    @State private var chosenWorkout: WorkoutChoice?
    @State private var errorText: String?
    @State private var checkedRecovery = false
    /// Prazna Početna je jednom dobila zadane kartice (ključ je ostao od kartice zadnjeg treninga).
    @AppStorage("dashboard.lastWorkoutSeeded") private var defaultsSeeded = false
    /// Početna je jednom prešla na karticu Ovaj tjedan (`DashboardLayout.upgradeToWeekCard`).
    @AppStorage("dashboard.weekCardUpgraded") private var weekCardUpgraded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var recovery: RecoveryPrompt?
    /// Ekran koji je otvorio widget (pregled tjedna, težina, zadnji trening), kao list preko Početne.
    @State private var widgetSheet: WidgetSheet?
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
                    ProfileSetupCard()
                    ForEach(cardRows, id: \.self) { row in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(row, id: \.self) { kind in
                                cardView(kind)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
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
                        Button(String("Prototipi"), systemImage: "hammer") {
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
            .sheet(item: $widgetSheet) { sheet in
                widgetSheetContent(sheet)
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
                prepareCards()
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
        // Ponovni dodir na tab: novi stog bez otvorenih ekrana (Apple HIG).
        .id(rootReset)
    }

    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }
    private var lastSession: Session? {
        Session.merged(finishedSessions, health: healthWorkouts).first
    }

    /// Redovi kartica: dvije uzastopne male kartice dijele red, a uz veliki tekst svaka je u svom redu.
    private var cardRows: [[DashboardCardKind]] {
        // Čitanje `orderIndex` drži ekran prijavljenim na premještanje kartica.
        _ = dashboardCards.map(\.orderIndex)
        var kinds = DashboardLayout.visible(dashboardCards).compactMap(\.kind)
        // Bez odrađenog treninga kartica zadnjeg treninga nema što pokazati.
        if lastSession == nil { kinds.removeAll { $0 == .lastWorkout } }
        if dynamicTypeSize.isAccessibilitySize { return kinds.map { [$0] } }
        return DashboardLayout.rows(kinds)
    }

    @ViewBuilder
    private func cardView(_ kind: DashboardCardKind) -> some View {
        switch kind {
        case .thisWeek: ThisWeekCard()
        case .thisMonth: PeriodCard(period: .month)
        case .thisYear: PeriodCard(period: .year)
        case .lastWorkout:
            if let last = lastSession {
                LastWorkoutCard(session: last, unit: unit)
            }
        case .bodyWeight: BodyWeightCard(unit: unit)
        case .plateCalculator: PlateCalculatorCard(unit: unit)
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
                    offersOtherWorkout: offersOtherWorkout(upcoming),
                    onChooseTemplate: { schedules in
                        pickerSchedules = schedules
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
            // Iz Live Activityja ili Prečaca: zatvara se ono što je otvoreno preko Početne i otvara puni ekran treninga.
            // Trening pokrenut iz Prečaca je u bazi i prije nego što ga @Query pokaže.
            guard let active = activeSessions.first ?? (try? GymQueries(context: context).activeSession()) else { return }
            let hadSheet = hasPresentedSheet
            dismissSheets()
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
        case .home:
            dismissSheets()
        case .week:
            openWidgetSheet(.week)
        case .bodyWeight:
            openWidgetSheet(.bodyWeight)
        case .lastWorkout:
            guard let last = lastSession else { return }
            openWidgetSheet(.session(last))
        case .session(let id):
            var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let session = try? context.fetch(descriptor).first else { return }
            openWidgetSheet(.session(session))
        case .startWorkout:
            // Iz widgeta ili kontrole aplikacija može imati otvoren list: puni ekran treninga čeka da se zatvori.
            if hasPresentedSheet {
                dismissSheets()
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    startNextWorkout()
                }
            } else {
                startNextWorkout()
            }
        }
    }

    /// Jednom po uređaju: prazna Početna dobiva zadane kartice, a postojeća prelazi na karticu Ovaj tjedan
    /// (tjedni volumen postaje Ovaj tjedan, sljedeći trening se uklanja).
    private func prepareCards() {
        guard !defaultsSeeded || !weekCardUpgraded else { return }
        if AppServices.isSyncRunning && SyncMonitor.shared.tracker.lastImport == nil { return }
        let layout = DashboardLayout(context: context)
        do {
            if !defaultsSeeded {
                // Na praznoj Početnoj zadane kartice već imaju Ovaj tjedan, pa prijelaz nije potreban.
                let seeded = try layout.seedDefaults()
                defaultsSeeded = true
                if !seeded.isEmpty { weekCardUpgraded = true }
            }
            if !weekCardUpgraded {
                try layout.upgradeToWeekCard()
                weekCardUpgraded = true
            }
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
            WorkoutLifecycle.finished(session, context: context, origin: .phone)
        } catch WorkoutError.nothingCompleted {
            // Bez završene serije nema što spremiti: trening se odbacuje.
            discard(session)
        } catch {
            errorText = String(localized: "Trening se nije mogao spremiti.")
        }
    }

    private func discard(_ session: Session) {
        WorkoutLifecycle.discard(session, context: context)
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

    /// List za izbor treninga: uz rasporede njihovi treninzi (sljedeći označen), svaki raspored u svom odjeljku,
    /// i ostali spremljeni; inače samo spremljeni.
    private func templatePicker(_ upcoming: [PlannedWorkout]) -> TemplatePickerSheet {
        var seen = Set<UUID>()
        let groups = pickerSchedules
            .filter { seen.insert($0.id).inserted }
            .map { schedule in
                ScheduleChoices(
                    schedule: schedule,
                    workouts: workoutChoices(schedule),
                    nextItemID: upcoming.first(where: { $0.schedule.id == schedule.id })?.item.id
                )
            }
            .filter { !$0.workouts.isEmpty }
        return TemplatePickerSheet(
            groups: groups,
            templates: startableTemplates,
            onSelect: { choice in chosenWorkout = choice }
        )
    }

    /// Treninzi rasporeda za izbor umjesto sljedećeg.
    private func workoutChoices(_ schedule: Schedule) -> [PlannedWorkout] {
        (try? ScheduleEngine(context: context).workoutChoices(of: schedule)) ?? []
    }

    /// Red "Odaberi drugi trening" ispod rasporeda: ima smisla kad postoji barem jedan trening snage osim sljedećih.
    private func offersOtherWorkout(_ upcoming: [PlannedWorkout]) -> Bool {
        let next = Set(upcoming.map(\.template.id))
        return startableTemplates.contains { !next.contains($0.id) }
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

// MARK: - Widgeti

/// Zahtjevi iz widgeta i kontrole: pokretanje treninga i listovi preko Početne.
extension HomeScreen {
    private func startNextWorkout() {
        guard presentedSession == nil else { return }
        if let active = activeSessions.first {
            presentedSession = active
        } else if let planned = upcomingWorkouts.first {
            start(planned)
        } else if !startableTemplates.isEmpty {
            pickerSchedules = []
            showsTemplatePicker = true
        } else {
            startWorkout()
        }
    }

    /// Je li preko Početne otvoren list ili dijalog. Novi list ili puni ekran treninga mora čekati da se zatvori.
    private var hasPresentedSheet: Bool {
        showsSettings || showsCardEditor || showsTemplatePicker || widgetSheet != nil || recovery != nil
    }

    /// Zatvara listove i dijalog oporavka preko Početne (dodir na widget vodi na čistu Početnu ili na jedan list).
    /// Trening u tijeku ostaje na kartici, pa se oporavak može nastaviti i odande.
    private func dismissSheets() {
        showsSettings = false
        showsCardEditor = false
        showsTemplatePicker = false
        chosenWorkout = nil
        widgetSheet = nil
        recovery = nil
    }

    /// Otvara list iz widgeta. Ako je nešto već otvoreno, prvo se zatvara, jer se novi list ne može prikazati
    /// dok se stari zatvara.
    private func openWidgetSheet(_ sheet: WidgetSheet) {
        let hadSheet = hasPresentedSheet
        dismissSheets()
        if hadSheet {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                widgetSheet = sheet
            }
        } else {
            widgetSheet = sheet
        }
    }

    @ViewBuilder
    private func widgetSheetContent(_ sheet: WidgetSheet) -> some View {
        NavigationStack {
            Group {
                switch sheet {
                case .week: OverviewScreen()
                case .bodyWeight: BodyScreen()
                case .session(let session): SessionDetailScreen(session: session, unit: unit)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Gotovo") { widgetSheet = nil }
                }
            }
        }
    }
}

/// List koji otvara widget.
private enum WidgetSheet: Identifiable {
    case week
    case bodyWeight
    case session(Session)

    var id: String {
        switch self {
        case .week: "week"
        case .bodyWeight: "bodyWeight"
        case .session(let session): "session-\(session.id.uuidString)"
        }
    }
}

private struct RecoveryPrompt: Identifiable {
    let session: Session
    let isStale: Bool
    var id: UUID { session.id }
}
