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
    @Query private var settingsList: [UserSettings]
    /// Vježbe za usporedbu, učitane jednom pri otvaranju.
    @State private var done: [DoneExercise] = []
    @State private var metric: Metric = .weight
    @State private var useBrzycki = false
    @State private var points: [ExercisePoint] = []
    /// Druga vježba na istom grafu (usporedba).
    @State private var compared: ExerciseRef?
    @State private var comparedPoints: [ExercisePoint] = []

    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }

    private func value(_ point: ExercisePoint) -> Double? {
        let kilograms: Double?
        switch metric {
        case .weight: kilograms = point.bestWeightKg
        case .oneRepMax: kilograms = point.estimatedOneRepMaxKg
        case .volume: kilograms = point.volumeKg
        }
        return kilograms.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }
    }

    private var plotted: [PlotPoint] {
        series(ref.name, points) + (compared.map { series($0.name, comparedPoints) } ?? [])
    }

    private func series(_ name: String, _ points: [ExercisePoint]) -> [PlotPoint] {
        points.compactMap { point in value(point).map { PlotPoint(series: name, date: point.date, value: $0) } }
    }

    var body: some View {
        List {
            Section {
                Picker("Prikaz", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if metric == .oneRepMax {
                    Toggle("Brzycki umjesto Epley", isOn: $useBrzycki)
                }
                if points.count < 2 && compared == nil {
                    Text("Za graf trebaju barem dva treninga s ovom vježbom.").foregroundStyle(.secondary)
                } else {
                    Chart(plotted) { item in
                        LineMark(x: .value("Datum", item.date), y: .value(unit.symbol, item.value))
                            .foregroundStyle(by: .value("Vježba", item.series))
                        PointMark(x: .value("Datum", item.date), y: .value(unit.symbol, item.value))
                            .foregroundStyle(by: .value("Vježba", item.series))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartLegend(compared == nil ? .hidden : .visible)
                    .chartHeight(220, regular: 360)
                    .accessibilityLabel(Text(chartLabel))
                }
                compareMenu
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
        .task { done = (try? DoneExercises.fetch(in: context)) ?? [] }
        .task(id: LoadKey(useBrzycki: useBrzycki, comparedKey: compared?.key)) {
            let engine = StatisticsEngine(context: context)
            let formula: SetMetrics.OneRepMaxFormula = useBrzycki ? .brzycki : .epley
            points = (try? engine.progress(of: ref, formula: formula)) ?? []
            comparedPoints = compared.flatMap { try? engine.progress(of: $0, formula: formula) } ?? []
        }
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
