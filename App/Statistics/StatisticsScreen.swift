import Catalog
import Charts
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Statistika: kartice s grafovima. Na iPadu se kartice slažu u više stupaca, a grafovi su viši.
struct StatisticsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }) private var ownSessions: [Session]
    /// Kardio iz Zdravlja (lokalna baza) broji se u učestalost treninga.
    @Query private var healthWorkouts: [HealthWorkout]
    private var sessionCount: Int { ownSessions.count + healthWorkouts.count }
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]

    @State private var setsWeeks = 4
    @State private var heatmapDays = 30
    @State private var weeklySets: [String: RegionLoad] = [:]
    @State private var buckets: [VolumeBucket] = []
    @State private var frequency: [FrequencyPoint] = []
    @State private var heatmap: [String: RegionLoad] = [:]
    @State private var trends: [StrengthTrend] = []
    @State private var records: [RecordEntry] = []
    @State private var review: WeeklyReview?
    @State private var suggestions: [Suggestion] = []
    @State private var effort = EffortDistribution()
    @State private var intensity = IntensityDistribution()

    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }
    private var isPro: Bool { settings?.statsDetail == .pro }

    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }

    private var trackedKinds: Set<PRKind> {
        PRKind.tracked(by: settings)
    }

    private var excludedExercises: Set<String> {
        settings?.prExcludedExerciseKeys ?? []
    }

    private struct LoadKey: Equatable {
        var sessionCount: Int
        var setsWeeks: Int
        var heatmapDays: Int
        var customCount: Int
        var goal: TrainingGoal?
        var plannedPerWeek: Int?
    }

    private struct RecordsKey: Equatable {
        var sessionCount: Int
        var kinds: Set<PRKind>
        var excluded: Set<String>
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if sessionCount == 0 {
                    ContentUnavailableView(
                        "Još nema statistike", systemImage: "chart.bar",
                        description: Text("Statistika se pojavi nakon prvog završenog treninga.")
                    )
                    .padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                    if sessionCount > 0 {
                        if let review {
                            WeeklyReviewCard(review: review, suggestions: suggestions, isPro: isPro)
                        }
                        SetsCard(weeks: $setsWeeks, loads: weeklySets)
                        ComparisonCard(comparison: VolumeComparison(buckets: buckets))
                        HeatmapCard(days: $heatmapDays, heatmap: heatmap, female: UserSettings.preferred(in: settingsList)?.bodyMapFemale ?? false)
                        StrengthTrendCard(trends: trends, isPro: isPro)
                        FrequencyCard(points: frequency)
                        RecordsCard(records: records, unit: unit)
                        if isPro {
                            EffortCard(distribution: effort)
                            IntensityCard(distribution: intensity)
                        }
                    }
                    ProgressCard()
                    BodyCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistika")
            .task(id: LoadKey(
                sessionCount: sessionCount, setsWeeks: setsWeeks, heatmapDays: heatmapDays, customCount: customExercises.count,
                goal: settings?.goal, plannedPerWeek: settings?.trainingDaysPerWeek
            )) { load() }
            // Rekordi prolaze cijelu povijest pa se ne računaju ponovno kad se promijeni samo razdoblje grafa.
            .task(id: RecordsKey(sessionCount: sessionCount, kinds: trackedKinds, excluded: excludedExercises)) { loadRecords() }
        }
    }

    private func load() {
        PerformanceSignpost.measure("Statistics") { compute() }
    }

    private func compute() {
        let engine = StatisticsEngine(context: context)
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        let now = Date()
        let end = now.addingTimeInterval(1)
        let setsStart = Calendar.current.date(byAdding: .day, value: -7 * setsWeeks, to: now) ?? now
        weeklySets = (try? engine.heatmap(from: setsStart, until: end, info: info)) ?? [:]
        buckets = (try? engine.volumeBuckets(size: .week, count: 2, info: info)) ?? []
        frequency = (try? engine.frequency(weeks: 12)) ?? []
        let start = Calendar.current.date(byAdding: .day, value: -heatmapDays, to: now) ?? now
        heatmap = (try? engine.heatmap(from: start, until: end, info: info)) ?? [:]
        trends = (try? engine.strengthTrends(weeks: 4, endingAt: end, info: info)) ?? []
        let weekly = try? engine.weeklyReview(
            endingAt: now, goal: settings?.goal, plannedPerWeek: settings?.trainingDaysPerWeek, info: info
        )
        review = weekly?.review
        suggestions = weekly?.suggestions ?? []
        let monthStart = now.addingTimeInterval(-28 * 24 * 3600)
        effort = (try? engine.effortDistribution(from: monthStart, until: end)) ?? EffortDistribution()
        intensity = (try? engine.intensityDistribution(from: monthStart, until: end)) ?? IntensityDistribution()
    }

    private func loadRecords() {
        PerformanceSignpost.measure("StatisticsRecords") {
            records = (try? StatisticsEngine(context: context).personalRecords(
                kinds: trackedKinds, excluding: excludedExercises
            )) ?? []
        }
    }
}

// MARK: - Kartica

extension View {
    /// Visina grafa: na iPadu (regular širina) graf je viši.
    func chartHeight(_ compact: CGFloat, regular: CGFloat) -> some View {
        modifier(ChartHeight(compact: compact, regular: regular))
    }
}

private struct ChartHeight: ViewModifier {
    let compact: CGFloat
    let regular: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.frame(height: sizeClass == .regular ? regular : compact)
    }
}

struct StatisticsCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.itemTitle)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.card))
    }
}

// MARK: - Serije po mišićima

/// Prosjek tvrdih serija tjedno po mišiću, s označenom zonom 10 do 20 serija.
private struct SetsCard: View {
    @Binding var weeks: Int
    let loads: [String: RegionLoad]

    /// Redak grafa. Id je regija, da graf ne crta sve iznova pri svakom iscrtavanju.
    private struct Entry: Identifiable {
        let region: String
        let name: String
        let sets: Double
        var id: String { region }
    }

    /// Glavni mišići uvijek (i s nula serija, da se vidi što zaostaje), ostali samo ako imaju serija.
    private var entries: [Entry] {
        BodyRegion.all
            .filter { BodyRegion.major.contains($0) || (loads[$0]?.weeklySets ?? 0) > 0 }
            .map { Entry(region: $0, name: BodyRegion.title($0), sets: loads[$0]?.weeklySets ?? 0) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.region < $1.region }
    }

    var body: some View {
        StatisticsCard(title: "Serije po mišiću tjedno") {
            Picker("Razdoblje", selection: $weeks) {
                Text("4 tjedna").tag(4)
                Text("12 tjedana").tag(12)
            }
            .pickerStyle(.segmented)
            let rows = entries
            Chart {
                RectangleMark(xStart: .value("Serije tjedno", 10.0), xEnd: .value("Serije tjedno", 20.0))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                ForEach(rows) { entry in
                    BarMark(x: .value("Serije tjedno", entry.sets), y: .value("Mišić", entry.name))
                        .foregroundStyle(BodyRegion.color(entry.region))
                }
            }
            .chartXScale(domain: 0.0...max(22.0, (rows.map(\.sets).max() ?? 0) + 2))
            .frame(height: CGFloat(rows.count) * 26 + 30)
            .accessibilityLabel(Text("Graf tvrdih serija tjedno po mišićima"))
            Text("Siva zona je 10 do 20 tvrdih serija tjedno, raspon u kojem istraživanja nalaze najbolji rast mišića. Serija u kojoj mišić pomaže broji se kao pola.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Usporedba s prethodnim tjednom

private struct ComparisonCard: View {
    let comparison: VolumeComparison?

    /// Stupac grafa. Id je stabilan (mišić i razdoblje), da graf ne crta sve iznova pri svakom iscrtavanju.
    private struct Entry: Identifiable {
        let muscle: String
        let series: String
        let sets: Double
        var id: String { "\(muscle)|\(series)" }
    }

    private var currentTitle: String { String(localized: "Ovaj tjedan") }
    private var previousTitle: String { String(localized: "Prošli tjedan") }

    /// Šest mišića s najviše serija, svaki s dva stupca (ovaj i prošli tjedan).
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
        StatisticsCard(title: "Usporedba s prethodnim") {
            if let comparison, !entries.isEmpty {
                Text(summary(comparison))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                .accessibilityLabel(Text("Graf usporedbe serija po mišićima s prošlim tjednom"))
            } else {
                Text("Usporedba se pojavi kad u ovom ili prethodnom razdoblju postoji trening.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Npr. "Ovaj tjedan dosad: 38 tvrdih serija. 8 % više nego prošli tjedan."
    private func summary(_ comparison: VolumeComparison) -> String {
        let current = String(localized: "Ovaj tjedan dosad: \(comparison.currentSets) tvrdih serija.")
        guard let change = comparison.change else { return current }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        let difference = change >= 0
            ? String(localized: "\(percent) više nego prošli tjedan.")
            : String(localized: "\(percent) manje nego prošli tjedan.")
        return current + " " + difference
    }
}

// MARK: - Trend snage

/// Mjesečna promjena procjene 1RM po mišiću u zadnjih 8 tjedana. Osnovni prikaz pokazuje najviše tri mišića
/// s najvećim i tri s najmanjim rastom, detaljni sve s brojem vježbi.
private struct StrengthTrendCard: View {
    let trends: [StrengthTrend]
    let isPro: Bool

    private var shown: [StrengthTrend] {
        guard !isPro, trends.count > 6 else { return trends }
        return Array(trends.prefix(3)) + Array(trends.suffix(3))
    }

    var body: some View {
        StatisticsCard(title: "Trend snage po mišićima") {
            if trends.isEmpty {
                Text("Trend se pojavi kad istu vježbu s težinom napraviš barem 4 puta u 8 tjedana.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Promjena procjene 1RM glavnih vježbi mjesečno, zadnjih 8 tjedana.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(shown, id: \.region) { trend in
                    LabeledContent {
                        Text(ChangeFormat.percent(trend.change))
                            .monospacedDigit()
                            .foregroundStyle(ChangeFormat.color(trend.change))
                    } label: {
                        Text(BodyRegion.title(trend.region))
                        if isPro {
                            Text("Vježbi: \(trend.exercises)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Frekvencija

private struct FrequencyCard: View {
    let points: [FrequencyPoint]

    private var average: Double {
        guard !points.isEmpty else { return 0 }
        return Double(points.reduce(0) { $0 + $1.sessions }) / Double(points.count)
    }

    var body: some View {
        StatisticsCard(title: "Treninga tjedno") {
            Text("Prosjek zadnjih 12 tjedana: \(average.formatted(.number.precision(.fractionLength(0...1))))")
                .font(.subheadline).foregroundStyle(.secondary)
            Chart(points, id: \.weekStart) { point in
                BarMark(
                    x: .value("Tjedan", point.weekStart, unit: .weekOfYear),
                    y: .value("Treninga", point.sessions)
                )
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartHeight(160, regular: 240)
            .accessibilityLabel(Text("Graf broja treninga po tjednima"))
        }
    }
}

// MARK: - Body heatmap

private struct HeatmapCard: View {
    @Binding var days: Int
    let heatmap: [String: RegionLoad]

    /// Spol tijela bira se samo u Postavkama.
    let female: Bool
    @State private var selected: String?

    /// Glavni mišići s manje od 5 tvrdih serija tjedno.
    private var lagging: [String] {
        BodyRegion.major.filter { (heatmap[$0]?.weeklySets ?? 0) < 5 }
    }

    var body: some View {
        StatisticsCard(title: "Opterećenje po dijelovima tijela") {
            Picker("Razdoblje", selection: $days) {
                Text("30 dana").tag(30)
                Text("90 dana").tag(90)
                Text("Godina").tag(365)
            }
            .pickerStyle(.segmented)
            HStack(alignment: .top, spacing: 8) {
                BodyFigureView(female: female, back: false, heatmap: heatmap, selected: $selected)
                BodyFigureView(female: female, back: true, heatmap: heatmap, selected: $selected)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Prikaz tijela s opterećenjem. \(summary)"))
            HeatmapLegend()
            Text(caption).font(.subheadline)
            if let selected, let detail = detail(selected) {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Boja pokazuje prosjek tvrdih serija tjedno. Serija u kojoj mišić pomaže broji se kao pola, a serija s RPE ispod 6 se ne broji. Dodirni dio tijela za detalje.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func weekly(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var summary: String {
        if heatmap.isEmpty { return String(localized: "Nema podataka.") }
        return heatmap
            .sorted { $0.value.weeklySets > $1.value.weeklySets }
            .prefix(3)
            .map { String(localized: "\(BodyRegion.title($0.key)): \(weekly($0.value.weeklySets)) serija tjedno") }
            .formatted(.list(type: .and))
    }

    private var caption: String {
        if let selected {
            return String(localized: "\(BodyRegion.title(selected)): \(weekly(heatmap[selected]?.weeklySets ?? 0)) serija tjedno")
        }
        if heatmap.isEmpty { return String(localized: "U ovom razdoblju još nema treninga.") }
        if lagging.isEmpty { return String(localized: "Svi glavni mišići imaju barem 5 tvrdih serija tjedno.") }
        let names = lagging.map { BodyRegion.title($0) }.formatted(.list(type: .and))
        return String(localized: "Ispod 5 serija tjedno: \(names)")
    }

    /// Učestalost i zadnji trening odabranog mišića.
    private func detail(_ region: String) -> String? {
        guard let load = heatmap[region] else { return nil }
        let frequency = String(localized: "Treninga tjedno: \(weekly(load.sessionsPerWeek))")
        guard let last = load.lastTrained else { return frequency }
        let relative = last.formatted(.relative(presentation: .named))
        return frequency + " · " + String(localized: "Zadnji put: \(relative)")
    }
}

/// Legenda fiksne skale heatmapa (`LoadScale.weeklyLevel`): četiri razine boje.
private struct HeatmapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tvrde serije tjedno").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                swatch(level: 1, Text("Ispod 5"))
                swatch(level: 2, Text("5 do 9"))
                swatch(level: 3, Text("10 do 20"))
                swatch(level: 4, Text("Iznad 20"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func swatch(level: Int, _ label: Text) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(BodyFigureView.fill(intensity: LoadScale.intensity(level: level)))
                .frame(width: 14, height: 14)
            label.font(.caption)
        }
    }
}

extension BodyRegion {
    static func title(_ region: String) -> String {
        switch region {
        case "chest": String(localized: "Prsa")
        case "shoulders": String(localized: "Ramena")
        case "biceps": String(localized: "Biceps")
        case "triceps": String(localized: "Triceps")
        case "forearms": String(localized: "Podlaktice")
        case "abs": String(localized: "Trbuh")
        case "quads": String(localized: "Prednja loža")
        case "hamstrings": String(localized: "Stražnja loža")
        case "innerThigh": String(localized: "Nutarnje bedro")
        case "outerThigh": String(localized: "Vanjsko bedro")
        case "traps": String(localized: "Trapez")
        case "upperBack": String(localized: "Gornja leđa")
        case "lats": String(localized: "Široki leđni")
        case "lowerBack": String(localized: "Donja leđa")
        case "glutes": String(localized: "Gluteusi")
        case "calves": String(localized: "Listovi")
        default: region
        }
    }
}

// MARK: - Rekordi

private struct RecordsCard: View {
    let records: [RecordEntry]
    let unit: WeightUnit

    var body: some View {
        StatisticsCard(title: "Osobni rekordi") {
            if records.isEmpty {
                Text("Rekordi se pojave kad nadmašiš ranije treninge.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(records.prefix(3).enumerated()), id: \.offset) { _, entry in
                    RecordRow(entry: entry, unit: unit)
                }
            }
            NavigationLink("Svi rekordi") { RecordsScreen(records: records, unit: unit) }
        }
    }
}

struct RecordRow: View {
    let entry: RecordEntry
    let unit: WeightUnit

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.exerciseName)
                Text("\(entry.record.kind.title) · \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(RecordFormat.value(entry.record, unit: unit)).font(.rowValue)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecordsScreen: View {
    let records: [RecordEntry]
    let unit: WeightUnit
    @State private var kinds: Set<PRKind> = []
    @State private var search = ""

    private var filtered: [RecordEntry] {
        records.filter { entry in
            (kinds.isEmpty || kinds.contains(entry.record.kind))
                && (search.isEmpty || entry.exerciseName.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Text("Nema rekorda za ovaj filter.").foregroundStyle(.secondary)
            }
            ForEach(Array(filtered.enumerated()), id: \.offset) { _, entry in
                RecordRow(entry: entry, unit: unit)
            }
        }
        .navigationTitle("Rekordi")
        .searchable(text: $search, prompt: "Vježba")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
            Menu("Filter", systemImage: kinds.isEmpty
                 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") {
                ForEach(PRKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { kinds.contains(kind) },
                        set: { isOn in
                            if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
                        }
                    ))
                }
                if !kinds.isEmpty { Button("Očisti filter") { kinds = [] } }
            }
            }
        }
    }
}

// MARK: - Napredak vježbe i tijelo

private struct ProgressCard: View {
    var body: some View {
        StatisticsCard(title: "Napredak vježbe") {
            Text("Težina, procjena 1RM i volumen kroz vrijeme za jednu vježbu.")
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink("Odaberi vježbu") { ExerciseProgressPicker() }
        }
    }
}

private struct BodyCard: View {
    var body: some View {
        StatisticsCard(title: "Tijelo") {
            Text("Težina, opsezi i vlastite mjere s grafovima.")
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink("Praćenje tijela") { BodyScreen() }
        }
    }
}
