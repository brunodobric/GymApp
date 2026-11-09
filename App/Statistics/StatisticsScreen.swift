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
    /// Mijenja se kad korisnik ponovno dodirne već otvoren tab: stog navigacije se vraća na korijen.
    var rootReset = 0

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
    @State private var week: WeekProgress?
    @State private var month: PeriodSummary?
    @State private var year: PeriodSummary?
    @State private var frequency: [FrequencyPoint] = []
    @State private var heatmap: [String: RegionLoad] = [:]
    @State private var trends: [StrengthTrend] = []
    @State private var records: [RecordEntry] = []
    @State private var review: WeeklyReview?
    @State private var suggestions: [Suggestion] = []
    @State private var effort = EffortDistribution()
    @State private var intensity = IntensityDistribution()
    @State private var dots: DotsScore?
    @State private var hasBodyWeight = false

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
        var sex: Sex?
        var isPro: Bool
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
                        if let week {
                            OverviewCard(week: week, month: month, year: year)
                        }
                        if let review {
                            WeeklyReviewCard(review: review, suggestions: suggestions, isPro: isPro)
                        }
                        SetsCard(weeks: $setsWeeks, loads: weeklySets)
                        HeatmapCard(days: $heatmapDays, heatmap: heatmap, female: UserSettings.preferred(in: settingsList)?.bodyMapFemale ?? false)
                        StrengthTrendCard(trends: trends, isPro: isPro)
                        FrequencyCard(points: frequency)
                        RecordsCard(records: records, unit: unit)
                        if isPro {
                            EffortCard(distribution: effort)
                            IntensityCard(distribution: intensity)
                            DotsCard(score: dots, sex: settings?.sex, hasBodyWeight: hasBodyWeight, unit: unit)
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
                goal: settings?.goal, plannedPerWeek: settings?.trainingDaysPerWeek, sex: settings?.sex, isPro: isPro
            )) { load() }
            // Rekordi prolaze cijelu povijest pa se ne računaju ponovno kad se promijeni samo razdoblje grafa.
            .task(id: RecordsKey(sessionCount: sessionCount, kinds: trackedKinds, excluded: excludedExercises)) { loadRecords() }
        }
        // Ponovni dodir na tab: novi stog bez otvorenih ekrana (Apple HIG).
        .id(rootReset)
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
        let isCardio = ExerciseInfoBuilder.isCardio(info)
        week = try? engine.weekProgress(now: now, goal: settings?.trainingDaysPerWeek, isCardio: isCardio)
        month = try? engine.periodSummary(.month, containing: now, now: now, goal: settings?.trainingDaysPerWeek, isCardio: isCardio)
        year = try? engine.periodSummary(.year, containing: now, now: now, goal: settings?.trainingDaysPerWeek, isCardio: isCardio)
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
        loadDots(engine: engine, endingAt: end)
    }

    /// DOTS samo u detaljnom prikazu, uz spol i zadnju upisanu tjelesnu težinu.
    private func loadDots(engine: StatisticsEngine, endingAt end: Date) {
        guard isPro else { dots = nil; return }
        let bodyWeight = (try? BodyTracking(context: context).latest(of: .weight))?.value
        hasBodyWeight = (bodyWeight ?? 0) > 0
        guard let sex = settings?.sex, let bodyWeight, bodyWeight > 0 else { dots = nil; return }
        dots = try? engine.dotsScore(bodyWeightKg: bodyWeight, sex: sex, endingAt: end)
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
            let scaleMax = max(22.0, (rows.map(\.sets).max() ?? 0) + 2)
            SetsBarList(
                rows: rows.map { .init(id: $0.region, name: $0.name, sets: $0.sets, color: BodyRegion.color($0.region)) },
                scaleMax: scaleMax
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Graf tvrdih serija tjedno po mišićima"))
            Text("Siva zona je 10 do 20 tvrdih serija tjedno, raspon u kojem istraživanja nalaze najbolji rast mišića. Serija u kojoj mišić pomaže broji se kao pola.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Vodoravni stupci serija po mišiću, složeni ručno (Grid), a ne kroz Swift Charts.
/// Os Y u Swift Chartsu crtala je nazive mišića unutar područja grafa, preko stupaca i mreže.
/// Ovdje je naziv u svom stupcu lijevo, a stupac, siva zona i crte mreže samo desno od njega.
private struct SetsBarList: View {
    struct Row: Identifiable {
        let id: String
        let name: String
        let sets: Double
        let color: Color
    }

    let rows: [Row]
    /// Gornja granica osi X (najmanje 22, da se vidi cijela zona 10 do 20).
    let scaleMax: Double

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 26
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 10

    /// Zona preporučenog volumena.
    private let zone = 10.0...20.0

    private var ticks: [Int] { Array(stride(from: 0, through: Int(scaleMax), by: 5)) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .accessibilityHidden(true)
                    // Modifikatori idu na ćelije, ne na GridRow: GridRow s modifikatorom Grid slaže kao jednu ćeliju.
                    plotCell { width in
                        Capsule()
                            .fill(row.color)
                            .frame(width: max(row.sets > 0 ? 3 : 0, width * row.sets / scaleMax), height: barHeight)
                    }
                    .frame(height: rowHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(row.name))
                    .accessibilityValue(Text(row.sets, format: .number.precision(.fractionLength(0...1))))
                }
            }
            GridRow {
                Color.clear.frame(width: 0, height: 0)
                GeometryReader { proxy in
                    ForEach(ticks, id: \.self) { tick in
                        Text(tick, format: .number)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize()
                            .offset(x: proxy.size.width * Double(tick) / scaleMax + 3)
                    }
                }
                .frame(height: rowHeight)
                .accessibilityHidden(true)
            }
        }
    }

    /// Ćelija s mrežom i sivom zonom u pozadini. Redovi se dodiruju (bez razmaka), pa zona i crte izgledaju neprekinuto.
    private func plotCell<Bar: View>(@ViewBuilder bar: @escaping (CGFloat) -> Bar) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: width * (zone.upperBound - zone.lowerBound) / scaleMax)
                    .offset(x: width * zone.lowerBound / scaleMax)
                ForEach(ticks, id: \.self) { tick in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1 / displayScale)
                        .offset(x: width * Double(tick) / scaleMax)
                }
                bar(width)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
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
struct HeatmapLegend: View {
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
