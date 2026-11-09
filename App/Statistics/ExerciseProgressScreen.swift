import Catalog
import Charts
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Popis vježbi koje je korisnik radio, za odabir grafa napretka.
struct ExerciseProgressPicker: View {
    @Environment(\.modelContext) private var context
    /// Vježbe se učitaju jednom pri otvaranju, a pretraga filtrira taj popis.
    @State private var done: [DoneExercise] = []
    @State private var search = ""

    private var items: [DoneExercise] {
        search.isEmpty ? done : done.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if items.isEmpty {
                Text("Nema vježbi za prikaz.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                if let ref = item.ref {
                    NavigationLink(item.name) { ExerciseProgressScreen(ref: ref) }
                }
            }
        }
        .navigationTitle("Napredak vježbe")
        .searchable(text: $search, prompt: "Vježba")
        .task { done = (try? DoneExercises.fetch(in: context)) ?? [] }
    }
}

/// Graf napretka jedne vježbe, uz mogućnost usporedbe s drugom vježbom na istom grafu.
struct ExerciseProgressScreen: View {
    let ref: ExerciseRef

    private enum Metric: String, CaseIterable, Identifiable {
        case weight, oneRepMax, volume
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .weight: "Težina"
            case .oneRepMax: "1RM"
            case .volume: "Volumen"
            }
        }
    }

    /// Odabir raspona grafa; vlastiti raspon koristi datume `customFrom` i `customTo`.
    private enum RangeChoice: String, CaseIterable, Identifiable {
        case month, twoMonths, sixMonths, year, all, custom
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .month: "1 mjesec"
            case .twoMonths: "2 mjeseca"
            case .sixMonths: "6 mjeseci"
            case .year: "Godina"
            case .all: "Sve"
            case .custom: "Vlastiti raspon"
            }
        }
    }

    /// Točka grafa. Id je stabilan (vježba i datum), da graf ne crta sve iznova pri svakom iscrtavanju.
    private struct PlotPoint: Identifiable {
        let series: String
        let date: Date
        let value: Double
        var id: String { "\(series)|\(date.timeIntervalSinceReferenceDate)" }
    }

    private struct LoadKey: Equatable {
        var useBrzycki: Bool
        var comparedKey: String?
    }

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var settingsList: [UserSettings]
    @Query private var customExercises: [CustomExercise]
    @State private var trend: ExerciseTrendEntry?
    @State private var repMaxes: [RepMaxEntry] = []
    @State private var bodyWeightKg: Double?
    /// Vježbe za usporedbu, učitane jednom pri otvaranju.
    @State private var done: [DoneExercise] = []
    @State private var metric: Metric = .weight
    @State private var rangeChoice: RangeChoice = .all
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var useBrzycki = false
    @State private var points: [ExercisePoint] = []
    /// Druga vježba na istom grafu (usporedba).
    @State private var compared: ExerciseRef?
    @State private var comparedPoints: [ExercisePoint] = []

    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }
    private var isPro: Bool { UserSettings.preferred(in: settingsList)?.statsDetail == .pro }

    private func value(_ point: ExercisePoint) -> Double? {
        let kilograms: Double?
        switch metric {
        case .weight: kilograms = point.bestWeightKg
        case .oneRepMax: kilograms = point.estimatedOneRepMaxKg
        case .volume: kilograms = point.volumeKg
        }
        return kilograms.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }
    }

    private var range: ChartRange {
        switch rangeChoice {
        case .month: .months(1)
        case .twoMonths: .months(2)
        case .sixMonths: .months(6)
        case .year: .months(12)
        case .all: .all
        case .custom: .custom(from: customFrom, to: customTo)
        }
    }

    private var plotted: [PlotPoint] {
        let now = Date.now
        return series(ref.name, range.filter(points, now: now))
            + (compared.map { series($0.name, range.filter(comparedPoints, now: now)) } ?? [])
    }

    /// Os x pokriva cijeli odabrani raspon, i kad su treninzi samo u dijelu njega; za "sve" od prve do zadnje točke.
    private func xDomain(_ plotted: [PlotPoint]) -> ClosedRange<Date> {
        if let interval = range.interval(now: .now) {
            return interval.start...interval.end
        }
        let dates = plotted.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return Date.now...Date.now }
        return first...last
    }

    private func series(_ name: String, _ points: [ExercisePoint]) -> [PlotPoint] {
        points.compactMap { point in value(point).map { PlotPoint(series: name, date: point.date, value: $0) } }
    }

    var body: some View {
        List {
            statusSection
            Section {
                Picker("Prikaz", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if metric == .oneRepMax && isPro {
                    Toggle("Brzycki umjesto Epley", isOn: $useBrzycki)
                }
                Picker("Raspon", selection: $rangeChoice) {
                    ForEach(RangeChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                if rangeChoice == .custom {
                    DatePicker("Od", selection: $customFrom, in: ...customTo, displayedComponents: .date)
                    DatePicker("Do", selection: $customTo, in: customFrom...Date.now, displayedComponents: .date)
                }
                let visible = plotted
                if points.count < 2 && compared == nil {
                    Text("Za graf trebaju barem dva treninga s ovom vježbom.").foregroundStyle(.secondary)
                } else if visible.isEmpty {
                    Text("U odabranom rasponu nema treninga s ovom vježbom.").foregroundStyle(.secondary)
                } else {
                    Chart(visible) { item in
                        LineMark(x: .value("Datum", item.date), y: .value(unit.symbol, item.value))
                            .foregroundStyle(by: .value("Vježba", item.series))
                        PointMark(x: .value("Datum", item.date), y: .value(unit.symbol, item.value))
                            .foregroundStyle(by: .value("Vježba", item.series))
                    }
                    .chartYScale(domain: ChartValueDomain.domain(for: visible.map(\.value)))
                    .chartXScale(domain: xDomain(visible))
                    .chartLegend(compared == nil ? .hidden : .visible)
                    .chartHeight(220, regular: 360)
                    .accessibilityLabel(Text(chartLabel))
                }
                compareMenu
            } footer: {
                if metric == .oneRepMax {
                    Text("Procjena 1RM računa se iz serija do 12 ponavljanja, uz ponavljanja u rezervi kad je upisan RPE ili RIR.")
                }
            }
            if isPro && !repMaxes.isEmpty {
                Section("Najteža serija po ponavljanjima") {
                    ForEach(repMaxes, id: \.reps) { entry in
                        LabeledContent {
                            Text(WeightFormatter(unit: unit).string(fromKilograms: entry.weightKg)).font(.rowValue)
                        } label: {
                            Text("\(entry.reps)+ ponavljanja")
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }
            }
            Section("Treninzi") {
                ForEach(Array(points.reversed().enumerated()), id: \.offset) { _, point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(WeightFormatter(unit: unit).string(fromKilograms: point.bestWeightKg) + " × \(point.bestReps)")
                                .font(.rowValue)
                            if let oneRepMax = point.estimatedOneRepMaxKg {
                                Text("1RM ≈ \(WeightFormatter(unit: unit).string(fromKilograms: oneRepMax))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            done = (try? DoneExercises.fetch(in: context)) ?? []
            let engine = StatisticsEngine(context: context)
            let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
            trend = try? engine.exerciseTrend(of: ref, info: info)
            repMaxes = (try? engine.repMaxTable(of: ref)) ?? []
            bodyWeightKg = (try? BodyTracking(context: context).latest(of: .weight))?.value
        }
        .task(id: LoadKey(useBrzycki: useBrzycki && isPro, comparedKey: compared?.key)) {
            let engine = StatisticsEngine(context: context)
            let formula: SetMetrics.OneRepMaxFormula = useBrzycki && isPro ? .brzycki : .epley
            points = (try? engine.progress(of: ref, formula: formula)) ?? []
            comparedPoints = compared.flatMap { try? engine.progress(of: $0, formula: formula) } ?? []
        }
    }

    /// Status napretka u zadnjih 8 tjedana; u detaljnom prikazu i relativna snaga.
    @ViewBuilder
    private var statusSection: some View {
        if let trend {
            Section {
                LabeledContent {
                    // Namjerno HStack, ne Label: Label kao vrijednost LabeledContenta u Listi preuzme raspored
                    // retka (redak se razvuče u visinu, a crta ispod retka počne tek kod statusa).
                    HStack(spacing: 6) {
                        Image(systemName: trend.trend.status.systemImage)
                            .accessibilityHidden(true)
                        Text(trend.trend.status.title)
                    }
                    .foregroundStyle(trend.trend.status.color)
                } label: {
                    Text("Zadnjih 8 tjedana")
                    if let change = trend.trend.monthlyChange {
                        Text("\(ChangeFormat.percent(change)) mjesečno")
                    }
                }
                if isPro, trend.measure == .oneRepMax, let latest = trend.trend.latest, let bodyWeightKg, bodyWeightKg > 0 {
                    LabeledContent("Relativna snaga") {
                        Text("\((latest / bodyWeightKg).formatted(.number.precision(.fractionLength(2)))) × tjelesna težina")
                    }
                }
            } footer: {
                Text(statusFooter(trend))
            }
        }
    }

    private func statusFooter(_ trend: ExerciseTrendEntry) -> String {
        let measure = trend.measure == .oneRepMax ? String(localized: "procjena 1RM") : String(localized: "najviše ponavljanja")
        guard trend.trend.status != .insufficientData else {
            return String(localized: "Status se pojavi nakon 4 izvođenja u 8 tjedana. Mjeri se \(measure).")
        }
        let noise = trend.trend.noise.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "Mjeri se \(measure). Napredak se računa tek kad je veći od uobičajenog kolebanja ove vježbe (oko \(noise) između treninga).")
    }

    private var chartLabel: String {
        if let compared {
            return String(localized: "Graf napretka vježbi \(ref.name) i \(compared.name)")
        }
        return String(localized: "Graf napretka vježbe \(ref.name)")
    }

    /// Odabir druge vježbe za usporedbu na istom grafu.
    private var compareMenu: some View {
        Menu {
            if compared != nil {
                Button("Bez usporedbe", systemImage: "xmark") { compared = nil }
            }
            ForEach(done.filter { $0.key != ref.key }) { item in
                Button(item.name) { compared = item.ref }
            }
        } label: {
            if let compared {
                Label("Usporedba: \(compared.name)", systemImage: "chart.line.uptrend.xyaxis")
            } else {
                Label("Usporedi s drugom vježbom", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }
}
