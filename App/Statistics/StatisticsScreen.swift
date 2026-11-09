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
    /// Završeni treninzi i treninzi iz Zdravlja; nil dok se ne prebroje (`compute`).
    @State private var sessionCount: Int?
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]

    /// Razdoblje kartice Mišići u danima (4 tjedna, 12 tjedana ili godina).
    @State private var muscleDays = 28
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
        /// Izmjena podataka (`DataVersion`).
        var version: Int
        var muscleDays: Int
        var customCount: Int
        var goal: TrainingGoal?
        var plannedPerWeek: Int?
        var sex: Sex?
        var isPro: Bool
    }

    private struct RecordsKey: Equatable {
        var version: Int
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
                    if let sessionCount, sessionCount > 0 {
                        if let week {
                            OverviewCard(week: week, month: month, year: year, frequency: frequency)
                        }
                        // Detaljni prikaz (kasnije plaćena verzija) dodaje kartice, a zajedničke izgledaju isto u oba prikaza.
                        // Kartica bez podataka se ne prikazuje; uvjet piše uz ocjenu u kartici Savjeti i u Postavkama.
                        if isPro {
                            if let review {
                                WeeklyReviewCard(review: review, suggestions: suggestions)
                            }
                            MusclesCard(days: $muscleDays, loads: heatmap, female: settings?.bodyMapFemale ?? false)
                            if !trends.isEmpty {
                                StrengthTrendCard(trends: trends)
                            }
                        }
                        RecordsCard(records: records, unit: unit)
                        if isPro {
                            if effort.rated > 0 || intensity.total > 0 {
                                EffortIntensityCard(effort: effort, intensity: intensity)
                            }
                            if let dots {
                                DotsCard(score: dots, unit: unit)
                            }
                        }
                    }
                    DetailsCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistika")
            .task(id: LoadKey(
                version: DataVersion.shared.value, muscleDays: muscleDays, customCount: customExercises.count,
                goal: settings?.goal, plannedPerWeek: settings?.trainingDaysPerWeek, sex: settings?.sex, isPro: isPro
            )) { load() }
            // Rekordi prolaze cijelu povijest pa se ne računaju ponovno kad se promijeni samo razdoblje grafa.
            .task(id: RecordsKey(version: DataVersion.shared.value, kinds: trackedKinds, excluded: excludedExercises)) { loadRecords() }
        }
        // Ponovni dodir na tab: novi stog bez otvorenih ekrana (Apple HIG).
        .id(rootReset)
    }

    private func load() {
        PerformanceSignpost.measure("Statistics") { compute() }
    }

    private func compute() {
        // Kardio iz Zdravlja (lokalna baza) broji se u učestalost treninga.
        let finished = FetchDescriptor<Session>(predicate: #Predicate { $0.stateRaw == "finished" })
        sessionCount = ((try? context.fetchCount(finished)) ?? 0) + ((try? context.fetchCount(FetchDescriptor<HealthWorkout>())) ?? 0)
        let engine = StatisticsEngine(context: context)
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        let now = Date()
        let end = now.addingTimeInterval(1)
        let isCardio = ExerciseInfoBuilder.isCardio(info)
        week = try? engine.weekProgress(now: now, goal: settings?.trainingDaysPerWeek, isCardio: isCardio)
        month = try? engine.periodSummary(.month, containing: now, now: now, goal: settings?.trainingDaysPerWeek, isCardio: isCardio)
        year = try? engine.periodSummary(.year, containing: now, now: now, goal: settings?.trainingDaysPerWeek, isCardio: isCardio)
        frequency = (try? engine.frequency(weeks: 12)) ?? []
        // Ostale kartice su samo u detaljnom prikazu, pa se u osnovnom ne računaju.
        guard isPro else {
            heatmap = [:]
            trends = []
            review = nil
            suggestions = []
            effort = EffortDistribution()
            intensity = IntensityDistribution()
            dots = nil
            return
        }
        let start = Calendar.current.date(byAdding: .day, value: -muscleDays, to: now) ?? now
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

// MARK: - Mišići

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

/// Mjesečna promjena procjene 1RM po mišiću u zadnjih 8 tjedana, s brojem vježbi (detaljni prikaz).
private struct StrengthTrendCard: View {
    let trends: [StrengthTrend]

    var body: some View {
        StatisticsCard(title: "Trend snage po mišićima") {
            Text("Promjena procjene 1RM glavnih vježbi mjesečno, zadnjih 8 tjedana.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(trends, id: \.region) { trend in
                LabeledContent {
                    Text(ChangeFormat.percent(trend.change))
                        .monospacedDigit()
                        .foregroundStyle(ChangeFormat.color(trend.change))
                } label: {
                    Text(BodyRegion.title(trend.region))
                    Text("Vježbi: \(trend.exercises)")
                }
            }
        }
    }
}

/// Mišići: mapa tijela s bojom prema prosjeku tvrdih serija tjedno i ispod nje stupci po mišiću sa zonom
/// 10 do 20 serija. Oba prikaza dijele isto razdoblje i iste podatke.
private struct MusclesCard: View {
    @Binding var days: Int
    let loads: [String: RegionLoad]

    /// Spol tijela bira se samo u Postavkama.
    let female: Bool
    @State private var selected: String?

    /// Glavni mišići s manje od 5 tvrdih serija tjedno.
    private var lagging: [String] {
        BodyRegion.major.filter { (loads[$0]?.weeklySets ?? 0) < 5 }
    }

    /// Glavni mišići uvijek (i s nula serija, da se vidi što zaostaje), ostali samo ako imaju serija.
    private var rows: [SetsBarList.Row] {
        BodyRegion.all
            .filter { BodyRegion.major.contains($0) || (loads[$0]?.weeklySets ?? 0) > 0 }
            .map { SetsBarList.Row(id: $0, name: BodyRegion.title($0), sets: loads[$0]?.weeklySets ?? 0, color: BodyRegion.color($0)) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.id < $1.id }
    }

    var body: some View {
        StatisticsCard(title: "Mišići") {
            Picker("Razdoblje", selection: $days) {
                Text("4 tjedna").tag(28)
                Text("12 tjedana").tag(84)
                Text("Godina").tag(365)
            }
            .pickerStyle(.segmented)
            HStack(alignment: .top, spacing: 8) {
                BodyFigureView(female: female, back: false, heatmap: loads, selected: $selected)
                BodyFigureView(female: female, back: true, heatmap: loads, selected: $selected)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Prikaz tijela s opterećenjem. \(summary)"))
            HeatmapLegend()
            Text(caption).font(.subheadline)
            if let selected, let detail = detail(selected) {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            let barRows = rows
            SetsBarList(rows: barRows, scaleMax: max(22.0, (barRows.map(\.sets).max() ?? 0) + 2))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Graf tvrdih serija tjedno po mišićima"))
            Text("""
                Prosjek tvrdih serija tjedno. Siva zona je 10 do 20 serija, raspon u kojem istraživanja nalaze \
                najbolji rast mišića. Serija u kojoj mišić pomaže broji se kao pola, a serija s RPE ispod 6 se ne \
                broji. Dodirni dio tijela za detalje.
                """)
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func weekly(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var summary: String {
        if loads.isEmpty { return String(localized: "Nema podataka.") }
        return loads
            .sorted { $0.value.weeklySets > $1.value.weeklySets }
            .prefix(3)
            .map { String(localized: "\(BodyRegion.title($0.key)): \(weekly($0.value.weeklySets)) serija tjedno") }
            .formatted(.list(type: .and))
    }

    private var caption: String {
        if let selected {
            return String(localized: "\(BodyRegion.title(selected)): \(weekly(loads[selected]?.weeklySets ?? 0)) serija tjedno")
        }
        if loads.isEmpty { return String(localized: "U ovom razdoblju još nema treninga.") }
        if lagging.isEmpty { return String(localized: "Svi glavni mišići imaju barem 5 tvrdih serija tjedno.") }
        let names = lagging.map { BodyRegion.title($0) }.formatted(.list(type: .and))
        return String(localized: "Ispod 5 serija tjedno: \(names)")
    }

    /// Učestalost i zadnji trening odabranog mišića.
    private func detail(_ region: String) -> String? {
        guard let load = loads[region] else { return nil }
        let frequency = String(localized: "Treninga tjedno: \(weekly(load.sessionsPerWeek))")
        guard let last = load.lastTrained else { return frequency }
        let relative = last.formatted(.relative(presentation: .named))
        return frequency + " · " + String(localized: "Zadnji put: \(relative)")
    }
}

/// Legenda fiksne skale heatmapa (`LoadScale.weeklyLevel`): četiri razine boje.
struct HeatmapLegend: View {
    @Environment(\.appAccent) private var accent
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
                .fill(BodyFigureView.fill(intensity: LoadScale.intensity(level: level), accent: accent))
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

/// Ulazi u detaljne ekrane: graf jedne vježbe i praćenje tijela.
private struct DetailsCard: View {
    var body: some View {
        StatisticsCard(title: "Detalji") {
            row(title: "Napredak vježbe", detail: "Težina, procjena 1RM i volumen kroz vrijeme za jednu vježbu.", systemImage: "chart.line.uptrend.xyaxis") {
                ExerciseProgressPicker()
            }
            Divider()
            row(title: "Tijelo", detail: "Težina, opsezi i vlastite mjere s grafovima.", systemImage: "figure.stand") {
                BodyScreen()
            }
        }
    }

    private func row<Destination: View>(
        title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
