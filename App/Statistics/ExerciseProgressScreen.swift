import Charts
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Popis vježbi koje je korisnik radio, za odabir grafa napretka.
struct ExerciseProgressPicker: View {
    @Query(filter: #Predicate<SessionExercise> { $0.isRemoved == false }) private var exercises: [SessionExercise]
    @State private var search = ""

    private struct Item: Identifiable, Hashable {
        let key: String
        let name: String
        var id: String { key }
    }

    private var items: [Item] {
        var seen = Set<String>()
        var result: [Item] = []
        for exercise in exercises where exercise.session?.state == .finished && !exercise.exerciseKey.isEmpty {
            if seen.insert(exercise.exerciseKey).inserted {
                result.append(Item(key: exercise.exerciseKey, name: exercise.exerciseName))
            }
        }
        let sorted = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return search.isEmpty ? sorted : sorted.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if items.isEmpty {
                Text("Nema vježbi za prikaz.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                if let ref = ExerciseRef(key: item.key, name: item.name) {
                    NavigationLink(item.name) { ExerciseProgressScreen(ref: ref) }
                }
            }
        }
        .navigationTitle("Napredak vježbe")
        .searchable(text: $search, prompt: "Vježba")
    }
}

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

    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @State private var metric: Metric = .weight
    @State private var useBrzycki = false
    @State private var points: [ExercisePoint] = []

    private var unit: WeightUnit { settingsList.first?.weightUnit ?? .kilograms }

    private func value(_ point: ExercisePoint) -> Double? {
        let kilograms: Double?
        switch metric {
        case .weight: kilograms = point.bestWeightKg
        case .oneRepMax: kilograms = point.estimatedOneRepMaxKg
        case .volume: kilograms = point.volumeKg
        }
        return kilograms.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }
    }

    private var plotted: [(date: Date, value: Double)] {
        points.compactMap { point in value(point).map { (point.date, $0) } }
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
                if plotted.count < 2 {
                    Text("Za graf trebaju barem dva treninga s ovom vježbom.").foregroundStyle(.secondary)
                } else {
                    Chart(plotted, id: \.date) { item in
                        LineMark(x: .value("Datum", item.date), y: .value(unit.symbol, item.value))
                        PointMark(x: .value("Datum", item.date), y: .value(unit.symbol, item.value))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    .accessibilityLabel(Text("Graf napretka vježbe \(ref.name)"))
                }
            }
            Section("Treninzi") {
                ForEach(Array(points.reversed().enumerated()), id: \.offset) { _, point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(WeightFormatter(unit: unit).string(fromKilograms: point.bestWeightKg) + " × \(point.bestReps)")
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
        .task(id: useBrzycki) {
            points = (try? StatisticsEngine(context: context)
                .progress(of: ref, formula: useBrzycki ? .brzycki : .epley)) ?? []
        }
    }
}
