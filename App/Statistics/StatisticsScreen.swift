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

    @State private var period: BucketSize = .week
    @State private var heatmapDays = 30
    @State private var buckets: [VolumeBucket] = []
    @State private var frequency: [FrequencyPoint] = []
    @State private var heatmap: [String: RegionLoad] = [:]
    @State private var records: [RecordEntry] = []

    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }

    private var trackedKinds: Set<PRKind> {
        PRKind.tracked(by: UserSettings.preferred(in: settingsList))
    }

    private struct LoadKey: Equatable {
        var sessionCount: Int
        var period: BucketSize
        var heatmapDays: Int
        var customCount: Int
    }

    private struct RecordsKey: Equatable {
        var sessionCount: Int
        var kinds: Set<PRKind>
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
                        VolumeCard(period: $period, buckets: buckets, unit: unit)
                        ComparisonCard(comparison: VolumeComparison(buckets: buckets), period: period, unit: unit)
                        FrequencyCard(points: frequency)
                        HeatmapCard(days: $heatmapDays, heatmap: heatmap, female: UserSettings.preferred(in: settingsList)?.bodyMapFemale ?? false)
                        RecordsCard(records: records, unit: unit)
                    }
                    ProgressCard()
                    BodyCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistika")
            .task(id: LoadKey(
                sessionCount: sessionCount, period: period, heatmapDays: heatmapDays, customCount: customExercises.count
            )) { load() }
            // Rekordi prolaze cijelu povijest pa se ne računaju ponovno kad se promijeni samo razdoblje grafa.
            .task(id: RecordsKey(sessionCount: sessionCount, kinds: trackedKinds)) { loadRecords() }
        }
    }

    private func load() {
        PerformanceSignpost.measure("Statistics") { compute() }
    }

    private func compute() {
        let engine = StatisticsEngine(context: context)
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        buckets = (try? engine.volumeBuckets(size: period, count: period == .week ? 8 : 6, info: info)) ?? []
        frequency = (try? engine.frequency(weeks: 12)) ?? []
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -heatmapDays, to: now) ?? now
        heatmap = (try? engine.heatmap(from: start, until: now.addingTimeInterval(1), info: info)) ?? [:]
    }

    private func loadRecords() {
        PerformanceSignpost.measure("StatisticsRecords") {
            records = (try? StatisticsEngine(context: context).personalRecords(kinds: trackedKinds)) ?? []
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

// MARK: - Volumen po mišićima

private struct VolumeCard: View {
    @Binding var period: BucketSize
    let buckets: [VolumeBucket]
    let unit: WeightUnit

    /// Stupac grafa. Id je stabilan (razdoblje i mišić), da graf ne crta sve iznova pri svakom iscrtavanju.
    private struct Entry: Identifiable {
        let start: Date
        let name: String
        let volume: Double
        var id: String { "\(start.timeIntervalSinceReferenceDate)|\(name)" }
    }

    /// Pet najopterećenijih mišića posebno, ostali zajedno.
    private var entries: [Entry] {
        var totals: [Muscle: Double] = [:]
        for bucket in buckets {
            for (muscle, load) in bucket.loads { totals[muscle, default: 0] += load.volumeKg }
        }
        let top = totals.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        let other = String(localized: "Ostalo")
        var result: [Entry] = []
        for bucket in buckets {
            var rest = 0.0
            for (muscle, load) in bucket.loads {
                if top.contains(muscle) {
                    result.append(Entry(
                        start: bucket.start, name: String(localized: muscle.title),
                        volume: WeightConversion.value(fromKilograms: load.volumeKg, in: unit)
                    ))
                } else {
                    rest += load.volumeKg
                }
            }
            if rest > 0 {
                result.append(Entry(
                    start: bucket.start, name: other, volume: WeightConversion.value(fromKilograms: rest, in: unit)
                ))
            }
        }
        return result
    }

    var body: some View {
        StatisticsCard(title: "Volumen po mišićima") {
            Picker("Razdoblje", selection: $period) {
                Text("Tjedni").tag(BucketSize.week)
                Text("Mjeseci").tag(BucketSize.month)
            }
            .pickerStyle(.segmented)
            if entries.isEmpty {
                Text("Nema podataka za ovo razdoblje.").foregroundStyle(.secondary)
            } else {
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Razdoblje", entry.start, unit: period == .week ? .weekOfYear : .month),
                        y: .value("Volumen (\(unit.symbol))", entry.volume)
                    )
                    .foregroundStyle(by: .value("Mišić", entry.name))
                }
                .chartHeight(220, regular: 320)
                .accessibilityLabel(Text("Graf volumena po mišićnim skupinama"))
            }
        }
    }
}

// MARK: - Usporedba s prethodnim razdobljem

private struct ComparisonCard: View {
    let comparison: VolumeComparison?
    let period: BucketSize
    let unit: WeightUnit

    /// Stupac grafa. Id je stabilan (mišić i razdoblje), da graf ne crta sve iznova pri svakom iscrtavanju.
    private struct Entry: Identifiable {
        let muscle: String
        let series: String
        let volume: Double
        var id: String { "\(muscle)|\(series)" }
    }

    private var currentTitle: String {
        period == .week ? String(localized: "Ovaj tjedan") : String(localized: "Ovaj mjesec")
    }

    private var previousTitle: String {
        period == .week ? String(localized: "Prošli tjedan") : String(localized: "Prošli mjesec")
    }

    /// Šest mišića s najvećim volumenom, svaki s dva stupca (ovo i prethodno razdoblje).
    private var entries: [Entry] {
        guard let comparison else { return [] }
        return comparison.muscles.prefix(6).flatMap { item in
            let name = String(localized: item.muscle.title)
            return [
                Entry(muscle: name, series: previousTitle, volume: WeightConversion.value(fromKilograms: item.previousKg, in: unit)),
                Entry(muscle: name, series: currentTitle, volume: WeightConversion.value(fromKilograms: item.currentKg, in: unit)),
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
                        y: .value("Volumen (\(unit.symbol))", entry.volume)
                    )
                    .foregroundStyle(by: .value("Razdoblje", entry.series))
                    .position(by: .value("Razdoblje", entry.series))
                }
                .chartForegroundStyleScale([previousTitle: Color.secondary.opacity(0.5), currentTitle: Color.accentColor])
                .chartHeight(220, regular: 320)
                .accessibilityLabel(Text("Graf usporedbe volumena po mišićima s prethodnim razdobljem"))
            } else {
                Text("Usporedba se pojavi kad u ovom ili prethodnom razdoblju postoji trening.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Npr. "Ovaj tjedan dosad: 12.300 kg, 8 % više nego prošli tjedan."
    private func summary(_ comparison: VolumeComparison) -> String {
        let formatter = WeightFormatter(unit: unit)
        let current = formatter.string(fromKilograms: comparison.currentKg)
        guard let change = comparison.change else {
            return String(localized: "\(currentTitle) dosad: \(current).")
        }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        if change >= 0 {
            return String(localized: "\(currentTitle) dosad: \(current), \(percent) više nego \(previousTitle.lowercased()).")
        }
        return String(localized: "\(currentTitle) dosad: \(current), \(percent) manje nego \(previousTitle.lowercased()).")
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

    private var top: [(region: String, load: RegionLoad)] {
        heatmap.sorted { $0.value.intensity > $1.value.intensity }.prefix(3).map { ($0.key, $0.value) }
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
            Text(caption).font(.subheadline)
            Text("Tamnija boja znači veće opterećenje. Dodirni dio tijela za broj treninga.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        if top.isEmpty { return String(localized: "Nema podataka.") }
        return top.map { "\(BodyRegion.title($0.region)): \($0.load.sessions)" }.joined(separator: ", ")
    }

    private var caption: String {
        if let selected {
            let sessions = heatmap[selected]?.sessions ?? 0
            return String(localized: "\(BodyRegion.title(selected)): \(sessions) treninga")
        }
        if top.isEmpty { return String(localized: "U ovom razdoblju još nema treninga.") }
        return String(localized: "Najopterećenije") + ": " + top.map { BodyRegion.title($0.region) }.joined(separator: ", ")
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

extension PRKind {
    var title: String {
        switch self {
        case .maxWeight: String(localized: "Najveća težina")
        case .maxVolume: String(localized: "Najveći volumen serije")
        case .maxReps: String(localized: "Najviše ponavljanja")
        case .lowestAssistance: String(localized: "Najmanja pomoć")
        case .longestDuration: String(localized: "Najduže trajanje")
        case .longestDistance: String(localized: "Najveća udaljenost")
        }
    }
}

enum RecordFormat {
    static func value(_ record: PersonalRecord, unit: WeightUnit) -> String {
        switch record.kind {
        case .maxWeight, .maxVolume, .lowestAssistance:
            return WeightFormatter(unit: unit).string(fromKilograms: record.value)
        case .maxReps:
            return String(localized: "\(Int(record.value)) pon.")
        case .longestDuration:
            let seconds = Int(record.value)
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .longestDistance:
            return record.value >= 1000
                ? String(localized: "\((record.value / 1000).formatted(.number.precision(.fractionLength(0...2)))) km")
                : String(localized: "\(Int(record.value)) m")
        }
    }
}

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
