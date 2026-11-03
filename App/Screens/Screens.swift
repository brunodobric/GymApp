import Models
import Planning
import SwiftData
import SwiftUI
import Training
import Units

// Privremeni ekrani za fazu 0. Svaki se zamjenjuje u fazi koja ga gradi.
// Naslovi su kratki (ispod 15 znakova) i nisu naziv aplikacije, prema HIG-u.

struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Session> { $0.stateRaw == "active" }, sort: \Session.startedAt, order: .reverse)
    private var activeSessions: [Session]

    @Query private var schedules: [Schedule]
    @Query private var cycleOverrides: [CycleOverride]
    @State private var showsSettings = false
    @State private var presentedSession: Session?
    @State private var errorText: String?
    @State private var checkedRecovery = false
    @State private var recovery: RecoveryPrompt?
    #if DEBUG
    @State private var showsPrototypes = false
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                if let active = activeSessions.first {
                    Text("Trening je u tijeku")
                        .font(.title2.bold())
                    Button("Nastavi trening", systemImage: "play.fill") { presentedSession = active }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Text("Spremni za trening")
                        .font(.title2.bold())
                    ForEach(upcomingWorkouts, id: \.item.id) { planned in
                        Button {
                            start(planned)
                        } label: {
                            VStack(spacing: 2) {
                                Label("Započni: \(planned.template.name)", systemImage: "play.fill")
                                Text(planned.schedule.name).font(.caption)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if upcomingWorkouts.isEmpty {
                        Button("Započni trening", systemImage: "plus") { startWorkout() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    } else {
                        Button("Prazan trening", systemImage: "plus") { startWorkout() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Početna")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Postavke", systemImage: "gearshape") {
                        showsSettings = true
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button("Prototipi", systemImage: "hammer") {
                        showsPrototypes = true
                    }
                }
                #endif
            }
            .sheet(isPresented: $showsSettings) {
                SettingsScreen()
            }
            .fullScreenCover(item: $presentedSession) { session in
                ActiveWorkoutScreen(session: session)
            }
            .task { checkRecovery() }
            .confirmationDialog(
                LocalizedStringKey(recovery?.isStale == true ? "Zaboravljen trening" : "Prekinut trening"),
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

    /// Pri pokretanju aplikacije: ako je trening ostao otvoren, nudi nastavak, spremanje ili odbacivanje.
    private func checkRecovery() {
        guard !checkedRecovery else { return }
        checkedRecovery = true
        guard let active = activeSessions.first, presentedSession == nil else { return }
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
        } catch WorkoutError.nothingCompleted {
            // Bez završene serije nema što spremiti: trening se odbacuje.
            discard(session)
        } catch {
            errorText = String(localized: "Trening se nije mogao spremiti.")
        }
    }

    private func discard(_ session: Session) {
        RestNotifications.cancel()
        try? WorkoutEngine(context: context).discardSession(session)
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
            presentedSession = try TemplateStarter(context: context).start(planned)
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
    @State private var settings: UserSettings?

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
                    TrainingSettingsSection(settings: settings)
                }
                Section {
                    Picker("Tijelo na prikazu mišića", selection: Binding(
                        get: { settings?.bodyMapFemale ?? false },
                        set: { settings?.bodyMapFemale = $0 }
                    )) {
                        Text("Muško").tag(false)
                        Text("Žensko").tag(true)
                    }
                } header: {
                    Text("Prikaz")
                } footer: {
                    Text("Određuje koje se tijelo crta u statistici i u sažetku treninga.")
                }
                DataSettingsSection {
                    settings = try? GymQueries(context: context).settings()
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
                    // TODO(faza 13): javni URL pravila privatnosti.
                    LabeledContent("Pravila privatnosti", value: "Uskoro")
                }
            }
            .navigationTitle("Postavke")
            .task { settings = try? GymQueries(context: context).settings() }
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
