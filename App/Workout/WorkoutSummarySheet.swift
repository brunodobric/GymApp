import Catalog
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Sažetak nakon završetka treninga: trajanje, tonaža, tvrde serije, usporedba s prošlim izvođenjem istog
/// treninga, rezultat po vježbi, mišići, najviše tri istaknuta rekorda i bilješka. U detaljnom prikazu
/// statistike još odmor između serija i ocjena napora treninga.
struct WorkoutSummarySheet: View {
    let session: Session
    let summary: WorkoutSummary
    let unit: WeightUnit
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var settingsList: [UserSettings]
    @Query private var customExercises: [CustomExercise]
    @State private var notes: String
    @State private var heartRateText: String
    @State private var sessionRPE: Double?
    @State private var comparison: SessionComparison?
    @State private var results: [ExerciseResult] = []
    @State private var weekSets: [String: Double] = [:]

    init(session: Session, summary: WorkoutSummary, unit: WeightUnit, onClose: @escaping () -> Void) {
        self.session = session
        self.summary = summary
        self.unit = unit
        self.onClose = onClose
        _notes = State(initialValue: session.notes)
        _heartRateText = State(initialValue: NumberInput.format(session.averageHeartRate))
        _sessionRPE = State(initialValue: session.sessionRPE)
    }

    private var isPro: Bool { UserSettings.preferred(in: settingsList)?.statsDetail == .pro }

    private var hasCardio: Bool {
        session.orderedExercises.contains { $0.inputType == .durationDistance || $0.inputType == .duration }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Trajanje", value: durationText(summary.durationSeconds))
                    LabeledContent("Volumen", value: WeightFormatter(unit: unit).string(fromKilograms: summary.totalVolumeKg))
                    LabeledContent("Tvrde serije", value: "\(summary.hardSets)")
                    if let meters = session.distanceMeters {
                        LabeledContent("Udaljenost", value: "\(NumberInput.format(meters / 1000)) km")
                    }
                } footer: {
                    Text("Tvrde serije su radne serije bez onih s RPE ispod 6.")
                }
                if let comparison {
                    SessionComparisonSection(comparison: comparison, unit: unit)
                }
                recordsSection
                if !results.isEmpty {
                    Section("Vježbe") {
                        ForEach(results) { ExerciseResultRow(result: $0, unit: unit, showsRest: isPro) }
                    }
                }
                SessionMusclesSection(session: session, weekSets: weekSets)
                if isPro {
                    Section {
                        Picker("Napor treninga", selection: $sessionRPE) {
                            Text("Bez ocjene").tag(Double?.none)
                            ForEach(1...10, id: \.self) { value in
                                Text(verbatim: "\(value)").tag(Double?.some(Double(value)))
                            }
                        }
                    } footer: {
                        Text("Koliko je bio težak cijeli trening, od 1 do 10. Napor puta trajanje je opterećenje treninga (Foster i sur. 2001).")
                    }
                }
                if hasCardio {
                    Section("Kardio") {
                        HStack {
                            TextField("Prosječni puls", text: $heartRateText)
                                .keyboardType(.numberPad)
                            Text("otk/min").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Bilješka") {
                    TextField("Kako je prošlo?", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Sažetak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zatvori") { close() }
                }
            }
            .task {
                let engine = StatisticsEngine(context: context)
                comparison = try? engine.comparison(of: session)
                results = (try? engine.exerciseResults(of: session)) ?? []
                let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
                let week = try? engine.volumeBuckets(size: .week, count: 1, endingAt: session.startedAt, info: info)
                weekSets = week?.last?.loads.mapValues(\.sets) ?? [:]
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var recordsSection: some View {
        Section {
            if summary.records.isEmpty {
                Text("Danas nema novih rekorda.").foregroundStyle(.secondary)
            } else if summary.highlights.isEmpty {
                Text("Danas nema većih rekorda.").foregroundStyle(.secondary)
            }
            ForEach(summary.highlights, id: \.exerciseKey) { item in
                RecordHighlightRow(exerciseName: item.exerciseName, record: item.record, unit: unit)
            }
            if summary.otherRecordsCount > 0 {
                DisclosureGroup("Još manjih rekorda: \(summary.otherRecordsCount)") {
                    ForEach(otherRecords, id: \.offset) { _, item in
                        RecordHighlightRow(exerciseName: item.name, record: item.record, unit: unit)
                    }
                }
            }
        } header: {
            Text("Osobni rekordi")
        }
    }

    /// Rekordi koji nisu istaknuti.
    private var otherRecords: [(offset: Int, element: (name: String, record: PersonalRecord))] {
        let shown = Set(summary.highlights.map { "\($0.exerciseKey)|\($0.record.kind.rawValue)" })
        let rest = summary.records.flatMap { item in
            item.records
                .filter { !shown.contains("\(item.exerciseKey)|\($0.kind.rawValue)") }
                .map { (name: item.exerciseName, record: $0) }
        }
        return Array(rest.enumerated())
    }

    private func close() {
        session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        session.averageHeartRate = NumberInput.parse(heartRateText)
        session.sessionRPE = sessionRPE
        try? context.save()
        onClose()
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
