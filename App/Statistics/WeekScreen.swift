import Charts
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Pregled jednog tjedna: sažetak s promjenom prema tjednu prije, treninzi po danima, serije po mišiću
/// s mapom tijela i rekordi tjedna. Strelice listaju tjedne unatrag. Otvara se s kartice Ovaj tjedan
/// na Početnoj i iz Statistike.
struct WeekScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    /// Samo za osvježavanje kad se trening završi, obriše ili stigne iz Zdravlja.
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }) private var ownSessions: [Session]
    @Query private var healthWorkouts: [HealthWorkout]
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]

    /// 0 je tekući tjedan, -1 prošli i tako dalje.
    @State private var offset = 0
    @State private var data: WeekData?
    @State private var selectedRegion: String?

    /// Najviše toliko tjedana unatrag.
    private static let oldestOffset = -520

    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }
    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }

    private struct LoadKey: Equatable {
        var offset: Int
        var sessions: Int
        var custom: Int
        var goal: Int?
        var kinds: Set<PRKind>
        var excluded: Set<String>
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                weekPicker
                if let data {
                    WeekSummaryCard(current: data.current, previous: data.previous)
                    WeekDaysCard(data: data, unit: unit)
                    WeekMusclesCard(
                        comparison: data.comparison, heatmap: data.heatmap, isCurrentWeek: offset == 0,
                        female: settings?.bodyMapFemale ?? false, selected: $selectedRegion
                    )
                    if !data.records.isEmpty {
                        StatisticsCard(title: "Rekordi tjedna") {
                            ForEach(Array(data.records.enumerated()), id: \.offset) { _, entry in
                                RecordHighlightRow(exerciseName: entry.exerciseName, record: entry.record, unit: unit)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tjedan")
        .toolbar {
            if offset != 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ovaj tjedan") { offset = 0 }
                }
            }
        }
        .task(id: LoadKey(
            offset: offset, sessions: ownSessions.count + healthWorkouts.count, custom: customExercises.count,
            goal: settings?.trainingDaysPerWeek, kinds: PRKind.tracked(by: settings),
            excluded: settings?.prExcludedExerciseKeys ?? []
        )) { load() }
        .onChange(of: offset) { selectedRegion = nil }
    }

    /// Strelice za prethodni i sljedeći tjedan te raspon datuma.
    private var weekPicker: some View {
        HStack {
            Button("Prethodni tjedan", systemImage: "chevron.backward") { offset -= 1 }
                .disabled(offset <= Self.oldestOffset)
            Spacer(minLength: 8)
            Text(rangeText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            Button("Sljedeći tjedan", systemImage: "chevron.forward") { offset += 1 }
                .disabled(offset >= 0)
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
    }

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: offset, to: .now) ?? .now
    }

    /// Npr. "2. – 8. studenoga 2026."
    private var rangeText: String {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
              let last = calendar.date(byAdding: .day, value: 6, to: week.start) else { return "" }
        return (week.start..<last).formatted(.interval.day().month(.wide).year())
    }

    private func load() {
        PerformanceSignpost.measure("WeekOverview") {
            let engine = StatisticsEngine(context: context)
            let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
            let isCardio = ExerciseInfoBuilder.isCardio(info)
            let goal = settings?.trainingDaysPerWeek
            let calendar = Calendar.current
            let reference = referenceDate
            guard let current = try? engine.weekProgress(now: reference, goal: goal, isCardio: isCardio) else {
                data = nil
                return
            }
            let previousDate = calendar.date(byAdding: .weekOfYear, value: -1, to: reference) ?? reference
            let previous = try? engine.weekProgress(now: previousDate, goal: goal, isCardio: isCardio)
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: current.start) ?? reference
            let sessions = (try? engine.sessions(inWeekStarting: current.start)) ?? []
            let records = (try? engine.personalRecords(
                kinds: PRKind.tracked(by: settings), excluding: settings?.prExcludedExerciseKeys ?? []
            )) ?? []
            data = WeekData(
                current: current,
                previous: previous,
                days: current.sessionsByDay(sessions),
                figures: Dictionary(
                    sessions.map { ($0.id, SessionFigures(session: $0, isCardio: isCardio)) },
                    uniquingKeysWith: { first, _ in first }
                ),
                mixes: Dictionary(
                    sessions.map { ($0.id, SessionCardio.mix(of: $0, isCardio: isCardio)) },
                    uniquingKeysWith: { first, _ in first }
                ),
                comparison: VolumeComparison(
                    buckets: (try? engine.volumeBuckets(size: .week, count: 2, endingAt: reference, info: info)) ?? []
                ),
                heatmap: (try? engine.heatmap(from: current.start, until: end, info: info)) ?? [:],
                records: records.filter { $0.date >= current.start && $0.date < end }
            )
        }
    }
}

/// Sve što ekran tjedna prikazuje, učitano odjednom.
struct WeekData {
    let current: WeekProgress
    let previous: WeekProgress?
    /// Treninzi po danima, poravnato s `current.days`.
    let days: [[Session]]
    let figures: [UUID: SessionFigures]
    let mixes: [UUID: SessionMix]
    let comparison: VolumeComparison?
    let heatmap: [String: RegionLoad]
    /// Rekordi postavljeni u tjednu, od najnovijeg.
    let records: [RecordEntry]

    /// Broj rekorda postavljenih u treningu (rekord nosi početak svog treninga).
    func recordCount(of session: Session) -> Int {
        records.filter { $0.date == session.startedAt }.count
    }
}

// MARK: - Sažetak

/// Treninzi, ukupno vrijeme, tvrde serije i kardio, s promjenom prema tjednu prije.
private struct WeekSummaryCard: View {
    let current: WeekProgress
    let previous: WeekProgress?

    private var showsCardio: Bool {
        current.cardioSeconds >= 60 || (previous?.cardioSeconds ?? 0) >= 60
    }

    var body: some View {
        StatisticsCard(title: "Sažetak") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile(value: sessionsText, label: "Treninga", change: countChange(current.sessions, previous?.sessions))
                tile(value: WeekFormat.duration(current.totalSeconds), label: "Ukupno",
                     change: durationChange(current.totalSeconds, previous?.totalSeconds))
                tile(value: current.hardSets.formatted(), label: "Tvrde serije",
                     change: percentChange(current.hardSets, previous?.hardSets))
                if showsCardio {
                    tile(value: cardioText, label: "Kardio",
                         change: durationChange(TimeInterval(current.cardioSeconds), previous.map { TimeInterval($0.cardioSeconds) }))
                }
            }
            if previous != nil {
                Text("Promjene su u odnosu na tjedan prije.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var sessionsText: String {
        guard let goal = current.goal else { return current.sessions.formatted() }
        return String(localized: "\(current.sessions) od \(goal)")
    }

    private var cardioText: String {
        let time = WeekFormat.duration(TimeInterval(current.cardioSeconds))
        guard current.cardioMeters > 0 else { return time }
        return "\(time) · \(CardioText.distance(current.cardioMeters))"
    }

    private func tile(value: String, label: LocalizedStringKey, change: Change?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.metricSmall)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text(label).foregroundStyle(.secondary)
                if let change {
                    Text(verbatim: change.text).foregroundStyle(change.isUp ? Color.green : Color.secondary)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: CornerRadius.inner))
        .accessibilityElement(children: .combine)
    }

    private struct Change {
        let text: String
        let isUp: Bool
    }

    private func countChange(_ now: Int, _ before: Int?) -> Change? {
        guard let before, now != before else { return nil }
        let delta = now - before
        return Change(text: delta.formatted(.number.sign(strategy: .always())), isUp: delta > 0)
    }

    private func durationChange(_ now: TimeInterval, _ before: TimeInterval?) -> Change? {
        guard let before else { return nil }
        let delta = now - before
        guard abs(delta) >= 60 else { return nil }
        let sign = delta > 0 ? "+" : "−"
        return Change(text: sign + WeekFormat.duration(abs(delta)), isUp: delta > 0)
    }

    private func percentChange(_ now: Int, _ before: Int?) -> Change? {
        guard let before, before > 0, now != before else { return nil }
        let change = Double(now - before) / Double(before)
        return Change(text: ChangeFormat.percent(change), isUp: change > 0)
    }
}

enum WeekFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

// MARK: - Po danima

/// Dani tjedna s treninzima; dan bez treninga je odmor, a dani koji još nisu došli se ne prikazuju.
/// Dodir na trening otvara njegove detalje.
private struct WeekDaysCard: View {
    let data: WeekData
    let unit: WeightUnit

    private var shownDays: [Int] {
        let today = Calendar.current.startOfDay(for: .now)
        return data.current.days.indices.filter { data.current.days[$0].date <= today }
    }

    var body: some View {
        StatisticsCard(title: "Po danima") {
            VStack(spacing: 0) {
                ForEach(shownDays, id: \.self) { index in
                    let day = data.current.days[index]
                    let sessions = index < data.days.count ? data.days[index] : []
                    if index != shownDays.first { Divider() }
                    HStack(alignment: .top, spacing: 12) {
                        dayLabel(day.date)
                        VStack(spacing: 0) {
                            if sessions.isEmpty {
                                Text("Odmor")
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            }
                            ForEach(sessions, id: \.id) { session in
                                NavigationLink {
                                    SessionDetailScreen(session: session, unit: unit)
                                } label: {
                                    sessionRow(session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.day())
                .font(.headline)
        }
        .frame(width: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 10) {
            WorkoutKindIcon(mix: data.mixes[session.id] ?? .strength)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.itemTitle)
                Text(detail(session)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .contentShape(.rect)
    }

    /// Npr. "1 h 5 min · 18 serija · 2 rekorda" ili "45 min · 7,2 km".
    private func detail(_ session: Session) -> String {
        var parts: [String] = []
        if let figures = data.figures[session.id] {
            parts.append(WeekFormat.duration(figures.durationSeconds))
            if figures.hardSets > 0 { parts.append(String(localized: "\(figures.hardSets) serija")) }
            if let meters = figures.cardioMeters { parts.append(CardioText.distance(meters)) }
        }
        let records = data.recordCount(of: session)
        if records > 0 { parts.append(String(localized: "\(records) rekorda")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Serije po mišiću

/// Tvrde serije po mišiću u tjednu uz tjedan prije, i mapa tijela s opterećenjem tog tjedna.
private struct WeekMusclesCard: View {
    let comparison: VolumeComparison?
    let heatmap: [String: RegionLoad]
    let isCurrentWeek: Bool
    let female: Bool
    @Binding var selected: String?

    /// Stupac grafa. Id je stabilan (mišić i razdoblje), da graf ne crta sve iznova pri svakom iscrtavanju.
    private struct Entry: Identifiable {
        let muscle: String
        let series: String
        let sets: Double
        var id: String { "\(muscle)|\(series)" }
    }

    private var currentTitle: String {
        isCurrentWeek ? String(localized: "Ovaj tjedan") : String(localized: "Odabrani tjedan")
    }

    private var previousTitle: String {
        isCurrentWeek ? String(localized: "Prošli tjedan") : String(localized: "Tjedan prije")
    }

    /// Šest mišića s najviše serija, svaki s dva stupca (tjedan i tjedan prije).
    private var entries: [Entry] {
        guard let comparison else { return [] }
        return comparison.muscles.prefix(6).flatMap { item in
            let name = BodyRegion.title(item.region)
            return [
                Entry(muscle: name, series: previousTitle, sets: item.previousSets),
                Entry(muscle: name, series: currentTitle, sets: item.currentSets),
            ]
        }
    }

    var body: some View {
        StatisticsCard(title: "Serije po mišiću") {
            if heatmap.isEmpty {
                Text("U ovom tjednu nema serija snage.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    BodyFigureView(female: female, back: false, heatmap: heatmap, selected: $selected)
                    BodyFigureView(female: female, back: true, heatmap: heatmap, selected: $selected)
                }
                .accessibilityHidden(true)
                HeatmapLegend()
                if let selected {
                    let sets = (heatmap[selected]?.sets ?? 0).formatted(.number.precision(.fractionLength(0...1)))
                    Text("\(BodyRegion.title(selected)): \(sets) tvrdih serija")
                        .font(.subheadline)
                }
            }
            if !entries.isEmpty {
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Mišić", entry.muscle),
                        y: .value("Tvrde serije", entry.sets)
                    )
                    .foregroundStyle(by: .value("Razdoblje", entry.series))
                    .position(by: .value("Razdoblje", entry.series))
                }
                .chartForegroundStyleScale([previousTitle: Color.secondary.opacity(0.5), currentTitle: Color.accentColor])
                .chartHeight(220, regular: 320)
                .accessibilityLabel(Text("Graf serija po mišićima u tjednu i tjednu prije"))
                Text("Serija u kojoj mišić pomaže broji se kao pola, a serija s RPE ispod 6 se ne broji.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Kartica u Statistici

/// Tekući tjedan ukratko, s poveznicom na pregled tjedna.
struct WeekLinkCard: View {
    let progress: WeekProgress

    var body: some View {
        StatisticsCard(title: "Ovaj tjedan") {
            if let goal = progress.goal {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(progress.sessions, format: .number).font(.metric)
                    Text("od \(goal) treninga").font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("\(progress.sessions) treninga").font(.metric)
            }
            if progress.hardSets > 0 {
                Text("\(progress.hardSets) tvrdih serija")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink("Pregled tjedna") { WeekScreen() }
        }
    }
}
