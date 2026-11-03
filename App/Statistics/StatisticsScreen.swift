import Catalog
import Charts
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Statistika: kartice s grafovima. Na iPadu se kartice slažu u više stupaca.
struct StatisticsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }) private var sessions: [Session]
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]

    @State private var period: BucketSize = .week
    @State private var heatmapDays = 30
    @State private var buckets: [VolumeBucket] = []
    @State private var frequency: [FrequencyPoint] = []
    @State private var heatmap: [String: RegionLoad] = [:]
    @State private var records: [RecordEntry] = []

    private var unit: WeightUnit { settingsList.first?.weightUnit ?? .kilograms }

    private var trackedKinds: Set<PRKind> {
        guard let raw = settingsList.first?.trackedPRKinds else { return Set(PRKind.allCases) }
        return PRKind.kinds(fromSettings: raw)
    }

    private struct LoadKey: Equatable {
        var sessionCount: Int
        var period: BucketSize
        var heatmapDays: Int
        var customCount: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Još nema statistike", systemImage: "chart.bar",
                        description: Text("Statistika se pojavi nakon prvog završenog treninga.")
                    )
                    .padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                    if !sessions.isEmpty {
                        VolumeCard(period: $period, buckets: buckets, unit: unit)
                        FrequencyCard(points: frequency)
                        HeatmapCard(days: $heatmapDays, heatmap: heatmap)
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
                sessionCount: sessions.count, period: period, heatmapDays: heatmapDays, customCount: customExercises.count
            )) { load() }
        }
    }

    private func load() {
        let engine = StatisticsEngine(context: context)
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        buckets = (try? engine.volumeBuckets(size: period, count: period == .week ? 8 : 6, info: info)) ?? []
        frequency = (try? engine.frequency(weeks: 12)) ?? []
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -heatmapDays, to: now) ?? now
        heatmap = (try? engine.heatmap(from: start, until: now.addingTimeInterval(1), info: info)) ?? [:]
        records = (try? engine.personalRecords(kinds: trackedKinds)) ?? []
    }
}

// MARK: - Kartica

struct StatisticsCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Volumen po mišićima

private struct VolumeCard: View {
    @Binding var period: BucketSize
    let buckets: [VolumeBucket]
    let unit: WeightUnit

    private struct Entry: Identifiable {
        let id = UUID()
        let start: Date
        let name: String
        let volume: Double
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
                .frame(height: 220)
                .accessibilityLabel(Text("Graf volumena po mišićnim skupinama"))
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
            .frame(height: 160)
            .accessibilityLabel(Text("Graf broja treninga po tjednima"))
        }
    }
}

// MARK: - Body heatmap

private struct HeatmapCard: View {
    @Binding var days: Int
    let heatmap: [String: RegionLoad]

    @AppStorage("bodyMapFemale") private var female = false
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
            Picker("Tijelo", selection: $female) {
                Text("Muško").tag(false)
                Text("Žensko").tag(true)
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
            return "\(BodyRegion.title(selected)): \(sessions) treninga"
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
            Text(RecordFormat.value(entry.record, unit: unit)).font(.headline)
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
