import Models
import Planning
import SwiftData
import SwiftUI
import Training
import Units

// Privremeni ekrani za fazu 0. Svaki se zamjenjuje u fazi koja ga gradi.
// Naslovi su kratki (ispod 15 znakova) i nisu naziv aplikacije, prema HIG-u.

struct HomeScreen: View {
    /// Zahtjev iz tipkovničkog prečaca: pokretanje treninga ili Postavke.
    @Binding var request: HomeRequest?

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Session> { $0.stateRaw == "active" }, sort: \Session.startedAt, order: .reverse)
    private var activeSessions: [Session]

    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }, sort: \Session.startedAt, order: .reverse)
    private var finishedSessions: [Session]
    @Query(sort: \HealthWorkout.startedAt, order: .reverse) private var healthWorkouts: [HealthWorkout]
    @Query(sort: \DashboardCard.orderIndex) private var dashboardCards: [DashboardCard]
    @Query private var settingsList: [UserSettings]
    @Query private var schedules: [Schedule]
    @Query private var cycleOverrides: [CycleOverride]
    @State private var showsSettings = false
    @State private var showsCardEditor = false
    @State private var presentedSession: Session?
    /// Kardio iz rasporeda: pregled plana s uputom za sat umjesto pokretanja treninga.
    @State private var cardioSchedule: Schedule?
    @State private var errorText: String?
    @State private var checkedRecovery = false
    @State private var recovery: RecoveryPrompt?
    #if DEBUG
    @State private var showsPrototypes = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    startSection
                    if let last = lastSession {
                        LastWorkoutCard(session: last, unit: unit)
                    }
                    ForEach(visibleCards) { card in
                        if let kind = card.kind {
                            cardView(kind)
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
            .sheet(item: $cardioSchedule) { schedule in
                NavigationStack {
                    UpcomingWorkoutScreen(schedule: schedule)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Gotovo") { cardioSchedule = nil }
                            }
                        }
                }
            }
            .sheet(isPresented: $showsCardEditor) {
                DashboardEditor()
            }
            .fullScreenCover(item: $presentedSession) { session in
                ActiveWorkoutScreen(session: session)
            }
            .task { checkRecovery() }
            .onChange(of: request) { _, newValue in
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
            .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("U redu") {}
            } message: {
                Text(errorText ?? "")
            }
            #if DEBUG
            .sheet(isPresented: $showsPrototypes) {
                PrototypesView()
            }
            #endif
        }
    }

    private var unit: WeightUnit { UserSettings.preferred(in: settingsList)?.weightUnit ?? .kilograms }
    private var lastSession: Session? {
        Session.merged(Array(finishedSessions.prefix(1)), health: Array(healthWorkouts.prefix(1))).first
    }

    private var visibleCards: [DashboardCard] {
        _ = dashboardCards.map(\.orderIndex)
        return (try? DashboardLayout(context: context).cards()) ?? []
    }

    @ViewBuilder
    private func cardView(_ kind: DashboardCardKind) -> some View {
        switch kind {
        case .plateCalculator: PlateCalculatorCard(unit: unit)
        case .nextWorkout: NextWorkoutCard(planned: upcomingWorkouts)
        case .weeklyVolume: WeeklyVolumeCard(unit: unit)
        }
    }

    /// Veliki gumb "Započni" na vrhu: nastavak aktivnog treninga ili početak novog (iz rasporeda ili praznog).
    private var startSection: some View {
        VStack(spacing: 12) {
            if let active = activeSessions.first {
                Text("Trening je u tijeku").font(.title2.bold())
                Button("Nastavi trening", systemImage: "play.fill") { presentedSession = active }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                ForEach(upcomingWorkouts, id: \.item.id) { planned in
                    Button {
                        if planned.template.kind == .cardio {
                            cardioSchedule = planned.schedule
                        } else {
                            start(planned)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            if planned.template.kind == .cardio {
                                Label("Na satu: \(planned.template.name)", systemImage: "applewatch")
                            } else {
                                Label("Započni: \(planned.template.name)", systemImage: "play.fill")
                            }
                            Text(planned.schedule.name).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("home.startPlanned")
                }
                if upcomingWorkouts.isEmpty {
                    Button { startWorkout() } label: {
                        Label("Započni trening", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                } else {
                    Button("Prazan trening", systemImage: "plus") { startWorkout() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// ⌘N nastavlja trening u tijeku ili pokreće sljedeći iz rasporeda (prazan ako rasporeda nema),
    /// isto kao prvi gumb na Početnoj. Kardio se ne pokreće u aplikaciji, pa ⌘N tada otvara prazan trening.
    private func handle(_ request: HomeRequest) {
        guard presentedSession == nil else { return }
        switch request {
        case .settings:
            showsSettings = true
        case .startWorkout:
            if let active = activeSessions.first {
                presentedSession = active
            } else if let planned = upcomingWorkouts.first(where: { $0.template.kind != .cardio }) {
                start(planned)
            } else {
                startWorkout()
            }
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
        } catch {
            errorText = String(localized: "Trening se nije mogao pokrenuti.")
        }
    }

    private func startWorkout() {
        do {
            presentedSession = try WorkoutEngine(context: context).startSession(name: String(localized: "Trening"))
            ReminderScheduler.refresh(context: context)
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

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    // Postavke iz upita, a ne zapamćeni objekt: nakon sinkronizacije duplikat postavki može biti obrisan.
    @Query private var settingsList: [UserSettings]
    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }

    private var systemScheme: ColorScheme? {
        guard settings != nil else { return nil }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let settings {
                    AppearanceSettingsSection(settings: settings)
                    TrainingSettingsSection(settings: settings)
                    PlatesSettingsSection(settings: settings)
                    NotificationSettingsSection(settings: settings)
                    HealthSettingsSection(settings: settings)
                }
                SyncSettingsSection()
                DataSettingsSection {
                    // Nakon brisanja svih podataka Početna prikazuje onboarding, pa se list zatvara.
                    let fresh = try? GymQueries(context: context).settings()
                    if fresh?.onboardingCompleted == false { dismiss() }
                }
                Section("O aplikaciji") {
                    LabeledContent("Verzija", value: version)
                    // Atribucija kataloga (specifikacija, odjeljak 10), iako je javno vlasništvo.
                    Link(destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!) {
                        LabeledContent("Katalog vježbi", value: "free-exercise-db")
                    }
                    // Atribucija crteža tijela (MIT licenca zahtijeva copyright napomenu i tekst licence).
                    NavigationLink {
                        MuscleMapLicenseScreen()
                    } label: {
                        LabeledContent("Crteži tijela", value: "MuscleMap")
                    }
                    Link("Pravila privatnosti", destination: PrivacyPolicy.url)
                    NavigationLink("Dijagnostika") { DiagnosticsScreen() }
                }
            }
            .navigationTitle("Postavke")
            // Otvoreni list ne preuzima promjenu teme i boje iz korijena dok je prikazan, pa ih primjenjuje sam.
            // Za "Sustav" nil ne poništava već prisilno postavljenu shemu na prikazanom listu, pa se šalje
            // sistemska shema izričito.
            .preferredColorScheme(settings?.theme.colorScheme ?? systemScheme)
            .tint(settings?.accent.color ?? AccentChoice.blue.color)
            .task { _ = try? GymQueries(context: context).settings() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
        }
    }
}

/// Postavke treninga: jedinice, zadana pauza, RPE ili RIR i zvuk kraja odmora.
private struct TrainingSettingsSection: View {
    @Bindable var settings: UserSettings

    var body: some View {
        Section("Trening") {
            Picker("Jedinice", selection: $settings.weightUnit) {
                Text("Kilogrami").tag(WeightUnit.kilograms)
                Text("Funte").tag(WeightUnit.pounds)
            }
            Stepper(value: $settings.defaultRestSeconds, in: 15...600, step: 15) {
                LabeledContent("Zadana pauza") {
                    Text(Duration.seconds(settings.defaultRestSeconds), format: .time(pattern: .minuteSecond))
                }
            }
            Picker("Napor", selection: $settings.effortScale) {
                Text("RPE").tag(EffortScale.rpe)
                Text("RIR").tag(EffortScale.rir)
            }
            Toggle("Zvuk kraja odmora", isOn: $settings.restEndSoundEnabled)
            Toggle("Rekordi (PR)", isOn: $settings.prEnabled)
            if settings.prEnabled {
                ForEach(PRSettingOption.allCases) { option in
                    Toggle(option.title, isOn: option.binding(for: settings))
                        .padding(.leading)
                }
            }
        }
    }
}

/// Izvor i licenca crteža tijela za heatmap.
struct MuscleMapLicenseScreen: View {
    private var licenseText: String {
        let url = Bundle.main.resourceURL?.appendingPathComponent("BodyMap/LICENSE-MuscleMap.txt")
        let raw = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "MIT License"
        // Tvrdi prijelomi unutar odlomaka se spajaju da tekst teče po širini ekrana; prazni redovi
        // i stavke koje počinju s "- " ostaju zasebni odlomci.
        var paragraphs: [String] = []
        var current = ""
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("- ") {
                if !current.isEmpty { paragraphs.append(current) }
                current = text
            } else {
                current += current.isEmpty ? text : " " + text
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Crteži tijela u heatmapu preuzeti su iz projekta MuscleMap (MIT licenca).")
                Link("github.com/Jsplice/MuscleMap", destination: URL(string: "https://github.com/Jsplice/MuscleMap")!)
                Divider()
                Text(licenseText).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("MuscleMap")
        .navigationBarTitleDisplayMode(.inline)
    }
}
