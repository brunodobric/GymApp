import Models
import Planning
import Stats
import SwiftData
import SwiftUI
import Training
import Units

extension DashboardCardKind {
    var title: LocalizedStringKey {
        switch self {
        case .thisWeek: "Ovaj tjedan"
        case .thisMonth: "Ovaj mjesec"
        case .thisYear: "Ova godina"
        case .lastWorkout: "Zadnji trening"
        case .bodyWeight: "Tjelesna težina"
        case .plateCalculator: "Kalkulator ploča"
        }
    }

    var symbol: String {
        switch self {
        case .thisWeek: "target"
        case .thisMonth: "calendar"
        case .thisYear: "chart.bar.xaxis"
        case .lastWorkout: "clock.arrow.circlepath"
        case .bodyWeight: "figure.stand"
        case .plateCalculator: "scalemass"
        }
    }
}

/// Okvir kartice na Početnoj, istog izgleda kao kartice u statistici.
/// Kartica ispunjava visinu reda, pa su dvije male kartice u istom redu jednako visoke.
struct HomeCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    /// Vrsta treninga: naslov tada ima ikonu vrste (`WorkoutKindIcon`) umjesto `symbol`.
    var mix: SessionMix?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Naslov kartice je u boji svoje ikone (akcent iz Postavki).
            Group {
                if let mix {
                    Label { Text(title) } icon: { WorkoutKindIcon(mix: mix) }
                } else {
                    Label(title, systemImage: symbol)
                }
            }
                .font(.cardHeading)
                .textCase(.uppercase)
                .foregroundStyle(.tint)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.card))
    }
}

// MARK: - Ovaj tjedan

/// Tekući tjedan: odrađeni treninzi prema cilju iz onboardinga (dani tjedno), dani s vrstom treninga,
/// tvrde serije, kardio i ukupno vrijeme te niz tjedana s ispunjenim ciljem. Dodir otvara Pregled na tekućem tjednu.
struct ThisWeekCard: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    /// Samo za osvježavanje kad se trening završi, obriše ili stigne iz Zdravlja.
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }) private var sessions: [Session]
    @Query private var healthWorkouts: [HealthWorkout]
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]
    @State private var progress: WeekProgress?

    private var goal: Int? { UserSettings.preferred(in: settingsList)?.trainingDaysPerWeek }

    var body: some View {
        // Dodir otvara Pregled (tekući tjedan) iz statistike.
        NavigationLink {
            OverviewScreen()
        } label: {
            card
        }
        .buttonStyle(.plain)
        .task(id: RefreshKey(sessions: sessions.count, health: healthWorkouts.count, goal: goal, day: Calendar.current.startOfDay(for: .now))) {
            load()
        }
    }

    private var card: some View {
        HomeCard(title: DashboardCardKind.thisWeek.title, symbol: DashboardCardKind.thisWeek.symbol) {
            if let progress {
                summary(progress)
                if let fraction = progress.goalFraction {
                    ProgressView(value: fraction)
                        .accessibilityHidden(true)
                }
                WeekDaysStrip(progress: progress)
                if progress.sessions > 0 {
                    PeriodFigures(
                        hardSets: progress.hardSets, cardioSeconds: progress.cardioSeconds, totalSeconds: progress.totalSeconds
                    )
                }
            }
        }
    }

    private struct RefreshKey: Equatable {
        let sessions: Int
        let health: Int
        let goal: Int?
        let day: Date
    }

    /// "2 od 3 treninga" i niz tjedana.
    private func summary(_ progress: WeekProgress) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                count(progress)
                Spacer(minLength: 8)
                streak(progress)
            }
            VStack(alignment: .leading, spacing: 4) {
                count(progress)
                streak(progress)
            }
        }
    }

    /// S ciljem veliki broj i "od 3 treninga", a bez cilja samo broj treninga.
    @ViewBuilder
    private func count(_ progress: WeekProgress) -> some View {
        if let goal = progress.goal {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(progress.sessions, format: .number).font(.metric)
                Text("od \(goal) treninga").font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("\(progress.sessions) treninga").font(.metric)
        }
    }

    @ViewBuilder
    private func streak(_ progress: WeekProgress) -> some View {
        if progress.streakWeeks >= 2 {
            Label {
                Text("\(progress.streakWeeks) tjedana zaredom")
            } icon: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func load() {
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        progress = try? StatisticsEngine(context: context).weekProgress(goal: goal, isCardio: ExerciseInfoBuilder.isCardio(info))
    }
}

// MARK: - Zadnji trening

/// Zadnji odrađeni trening: koliko je prošlo, vrsta, trajanje, tvrde serije i najviše dva istaknuta
/// rekorda (isti izbor kao u sažetku nakon treninga). Dodir otvara detalje.
struct LastWorkoutCard: View {
    let session: Session
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]
    @State private var summary: WorkoutSummary?

    /// Najviše toliko rekorda na kartici; ostali su u detaljima treninga.
    private static let recordLimit = 2

    private var duration: String? {
        guard let end = session.endedAt else { return nil }
        return Duration.seconds(max(0, end.timeIntervalSince(session.startedAt)))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private var info: ExerciseInfoProvider {
        ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
    }

    var body: some View {
        NavigationLink {
            SessionDetailScreen(session: session, unit: unit)
        } label: {
            let mix = SessionCardio.mix(of: session, isCardio: ExerciseInfoBuilder.isCardio(info))
            HomeCard(title: DashboardCardKind.lastWorkout.title, symbol: session.kind.symbol, mix: mix) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.cardTitle).foregroundStyle(.primary)
                    Text(dateText).font(.subheadline).foregroundStyle(.secondary)
                    Text(detailText(mix)).font(.subheadline).foregroundStyle(.secondary)
                }
                if let highlights = summary?.highlights.prefix(Self.recordLimit), !highlights.isEmpty {
                    Divider()
                    ForEach(Array(highlights), id: \.exerciseKey) { item in
                        RecordHighlightRow(exerciseName: item.exerciseName, record: item.record, unit: unit)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: TaskKey(id: session.id, activity: session.lastActivityAt)) { load() }
    }

    private struct TaskKey: Equatable {
        let id: UUID
        let activity: Date
    }

    /// "Jučer · subota, 7. studenoga", s danom u tjednu i datumom bez godine.
    private var dateText: String {
        let relative = Self.relativeDay(session.startedAt)
        let date = session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(relative) · \(date)"
    }

    /// Danas, jučer ili "prije 3 dana", po kalendarskim danima (a ne po satima od treninga).
    static func relativeDay(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let text = formatter.localizedString(from: DateComponents(day: -max(days, 0)))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Vrsta, trajanje i tvrde serije, npr. "Snaga + kardio · 1 h 4 min · 18 serija".
    private func detailText(_ mix: SessionMix) -> String {
        var parts = [String(localized: mix.title)]
        if let duration { parts.append(duration) }
        if let hardSets = summary?.hardSets, hardSets > 0 {
            parts.append(String(localized: "\(hardSets) serija"))
        }
        return parts.joined(separator: " · ")
    }

    private func load() {
        // Trening iz Zdravlja nema serija ni rekorda.
        guard !session.isImportedFromWorkoutsApp else {
            summary = nil
            return
        }
        let settings = UserSettings.preferred(in: settingsList)
        let provider = info
        summary = try? WorkoutEngine(context: context).summary(
            of: session, trackedKinds: PRKind.tracked(by: settings),
            excludedExercises: settings?.prExcludedExerciseKeys ?? [],
            isCompound: { provider($0)?.isCompound }, isCardio: ExerciseInfoBuilder.isCardio(provider)
        )
    }
}

// MARK: - Male kartice

/// Tjelesna težina: zadnja vrijednost i promjena u zadnjih 30 dana. Dodir otvara praćenje tijela.
struct BodyWeightCard: View {
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    /// Samo za osvježavanje kad se doda mjerenje ili stigne iz Zdravlja.
    @Query private var manual: [BodyMeasurement]
    @Query private var fromHealth: [HealthMeasurement]
    @State private var latest: Double?
    @State private var change: Double?

    var body: some View {
        NavigationLink {
            BodyScreen()
        } label: {
            HomeCard(title: "Težina", symbol: DashboardCardKind.bodyWeight.symbol) {
                if let latest {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BodyFormat.text(latest, kind: .weight, unit: unit))
                            .font(.metricSmall)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let change {
                            Text("\(BodyFormat.change(change, kind: .weight, unit: unit)) u 30 dana")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Upiši težinu")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: manual.count + fromHealth.count) { load() }
    }

    private func load() {
        let tracking = BodyTracking(context: context)
        latest = (try? tracking.latest(of: .weight))?.value
        change = try? tracking.recentChange(of: .weight)
    }
}

/// Kalkulator ploča kao mala kartica: dodir otvara kalkulator preko cijelog ekrana.
struct PlateCalculatorCard: View {
    let unit: WeightUnit

    var body: some View {
        NavigationLink {
            PlateCalculatorScreen(unit: unit)
        } label: {
            HomeCard(title: "Ploče", symbol: DashboardCardKind.plateCalculator.symbol) {
                Text("Kalkulator ploča")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Dodavanje, uklanjanje i premještanje kartica.
struct DashboardEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DashboardCard.orderIndex) private var stored: [DashboardCard]
    @State private var errorText: String?

    private var layout: DashboardLayout { DashboardLayout(context: context) }
    private var shown: [DashboardCard] {
        _ = stored.map(\.orderIndex)
        return (try? layout.cards()) ?? []
    }
    private var available: [DashboardCardKind] {
        _ = stored.count
        return (try? layout.availableKinds()) ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { card in
                        if let kind = card.kind {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                    .onMove { offsets, destination in
                        perform { try layout.move(fromOffsets: offsets, toOffset: destination) }
                    }
                    .onDelete { offsets in
                        let cards = shown
                        perform { for index in offsets { try layout.remove(cards[index]) } }
                    }
                } header: {
                    Text("Na Početnoj")
                } footer: {
                    if shown.isEmpty { Text("Nema kartica. Dodaj ih ispod.") }
                }
                if !available.isEmpty {
                    Section("Dodaj") {
                        ForEach(available, id: \.self) { kind in
                            Button {
                                perform { try layout.add(kind) }
                            } label: {
                                Label(kind.title, systemImage: "plus.circle.fill")
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Kartice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
            .errorAlert($errorText)
        }
    }

    private func perform<T>(_ change: () throws -> T) {
        do { _ = try change() } catch { errorText = String(localized: "Promjena se nije mogla spremiti.") }
    }
}
