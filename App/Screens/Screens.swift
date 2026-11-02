import Models
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

    @State private var showsSettings = false
    @State private var presentedSession: Session?
    @State private var errorText: String?
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
                    Button("Započni trening", systemImage: "plus") { startWorkout() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
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

    private func startWorkout() {
        do {
            presentedSession = try WorkoutEngine(context: context).startSession(name: String(localized: "Trening"))
        } catch {
            errorText = String(localized: "Trening se nije mogao pokrenuti.")
        }
    }
}

struct HistoryScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Još nema treninga",
                systemImage: "clock",
                description: Text("Ovdje će biti svi odrađeni treninzi.")
            )
            .navigationTitle("Povijest")
        }
    }
}

struct SchedulesScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nema rasporeda",
                systemImage: "calendar",
                description: Text("Ovdje ćeš slagati svoje rasporede treninga.")
            )
            .navigationTitle("Rasporedi")
        }
    }
}

struct StatisticsScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Još nema podataka",
                systemImage: "chart.bar",
                description: Text("Statistika se prikazuje nakon prvih treninga.")
            )
            .navigationTitle("Statistika")
        }
    }
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
                Section("O aplikaciji") {
                    LabeledContent("Verzija", value: version)
                    // Atribucija kataloga (specifikacija, odjeljak 10), iako je javno vlasništvo.
                    Link(destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!) {
                        LabeledContent("Katalog vježbi", value: "free-exercise-db")
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
