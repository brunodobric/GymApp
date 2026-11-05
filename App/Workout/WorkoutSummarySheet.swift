import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Sažetak nakon završetka treninga: trajanje, volumen, serije, osobni rekordi i bilješka.
struct WorkoutSummarySheet: View {
    let session: Session
    let summary: WorkoutSummary
    let unit: WeightUnit
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @State private var notes: String
    @State private var heartRateText: String

    init(session: Session, summary: WorkoutSummary, unit: WeightUnit, onClose: @escaping () -> Void) {
        self.session = session
        self.summary = summary
        self.unit = unit
        self.onClose = onClose
        _notes = State(initialValue: session.notes)
        _heartRateText = State(initialValue: NumberInput.format(session.averageHeartRate))
    }

    private var hasCardio: Bool {
        session.orderedExercises.contains { $0.inputType == .durationDistance || $0.inputType == .duration }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Trajanje", value: durationText(summary.durationSeconds))
                    LabeledContent("Volumen", value: WeightFormatter(unit: unit).string(fromKilograms: summary.totalVolumeKg))
                    LabeledContent("Završene serije", value: "\(summary.completedSets)")
                    if let meters = session.distanceMeters {
                        LabeledContent("Udaljenost", value: "\(NumberInput.format(meters / 1000)) km")
                    }
                }
                SessionMusclesSection(session: session)
                Section("Osobni rekordi") {
                    if summary.records.isEmpty {
                        Text("Danas nema novih rekorda.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.records, id: \.exerciseName) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.exerciseName).font(.headline)
                                ForEach(item.records, id: \.kind) { record in
                                    Label(recordText(record), systemImage: "trophy.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
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
        }
        .interactiveDismissDisabled()
    }

    private func close() {
        session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        session.averageHeartRate = NumberInput.parse(heartRateText)
        try? context.save()
        onClose()
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func recordText(_ record: PersonalRecord) -> String {
        let formatter = WeightFormatter(unit: unit)
        switch record.kind {
        case .maxWeight:
            return String(localized: "Najveća težina \(formatter.string(fromKilograms: record.value))")
        case .maxVolume:
            return String(localized: "Najveći volumen serije \(formatter.string(fromKilograms: record.value))")
        case .maxReps:
            return String(localized: "Najviše ponavljanja \(Int(record.value))")
        case .lowestAssistance:
            return String(localized: "Najmanja pomoć \(formatter.string(fromKilograms: record.value))")
        case .longestDuration:
            return String(localized: "Najdulje trajanje \(DurationInput.format(Int(record.value)))")
        case .longestDistance:
            return String(localized: "Najveća udaljenost \(NumberInput.format(record.value / 1000)) km")
        }
    }
}
