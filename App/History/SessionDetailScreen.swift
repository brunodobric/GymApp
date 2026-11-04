import Catalog
import Models
import SwiftData
import SwiftUI
import Stats
import Units

/// Detalji odrađenog treninga: sve vježbe, sve serije po vježbi i bilješke na dnu. Trening se može obrisati.
struct SessionDetailScreen: View {
    let session: Session
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var errorText: String?

    /// Kalorije i puls su u lokalnoj bazi podataka iz Zdravlja.
    private var health: HealthLocalStore { HealthLocalStore(context: context) }

    var body: some View {
        List {
            Section {
                LabeledContent("Datum", value: session.startedAt.formatted(date: .complete, time: .shortened))
                if let end = session.endedAt {
                    LabeledContent("Trajanje", value: Duration.seconds(max(0, end.timeIntervalSince(session.startedAt)))
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
                if let meters = session.distanceMeters {
                    LabeledContent("Udaljenost", value: "\(NumberInput.format(meters / 1000)) km")
                }
                if let heartRate = health.averageHeartRate(of: session) {
                    LabeledContent("Prosječni puls", value: String(localized: "\(Int(heartRate)) otk/min"))
                }
                // Kalorije samo iz Zdravlja; bez njih se redak ne prikazuje (ni nula ni procjena).
                if let energy = health.activeEnergy(of: session) {
                    LabeledContent("Aktivne kalorije", value: "\(Int(energy.rounded())) kcal")
                }
            } footer: {
                if session.isImportedFromWorkoutsApp {
                    Text("Uvezeno iz Zdravlja.")
                } else if session.healthKitWorkoutId != nil {
                    Text("Spremljeno u Zdravlje.")
                }
            }
            ForEach(session.orderedExercises.filter { !$0.isRemoved }) { exercise in
                Section(exercise.exerciseName) {
                    ForEach(Array(exercise.orderedSets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                        SetLine(set: set, inputType: exercise.inputType, unit: unit, number: number(of: set, in: exercise, fallback: index))
                    }
                }
            }
            if !session.notes.isEmpty {
                Section("Bilješke") {
                    Text(session.notes)
                }
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Obriši", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            }
        }
        .confirmationDialog("Obrisati trening?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Obriši trening", role: .destructive) { delete() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Trening i njegove serije bit će trajno obrisani, a rekordi i statistika preračunat će se bez njega.")
        }
        .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("U redu") {}
        } message: {
            Text(errorText ?? "")
        }
    }

    /// Redni broj radne serije; zagrijavanje nema broj.
    private func number(of set: SetLog, in exercise: SessionExercise, fallback: Int) -> Int? {
        guard set.kind == .working else { return nil }
        let working = exercise.orderedSets.filter { $0.isCompleted && $0.kind == .working }
        return (working.firstIndex { $0.id == set.id } ?? fallback) + 1
    }

    private func delete() {
        do {
            try HistoryQueries(context: context).delete(session)
            dismiss()
        } catch {
            errorText = String(localized: "Trening se nije mogao obrisati.")
        }
    }
}

private struct SetLine: View {
    let set: SetLog
    let inputType: ExerciseInputType
    let unit: WeightUnit
    let number: Int?

    var body: some View {
        HStack(spacing: 10) {
            SetBadge(kind: set.kind, number: number)
            Text(text)
            Spacer()
            if let rpe = set.rpe {
                Text("RPE \(NumberInput.format(rpe))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // VoiceOver čita cijeli redak kao rečenicu ("Serija 2, 80 kg, 8 ponavljanja") umjesto znaka ×.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var spokenText: Text {
        let formatter = WeightFormatter(unit: unit)
        let reps = set.reps ?? 0
        let values: String
        switch inputType {
        case .weightReps:
            values = String(localized: "\(formatter.string(fromKilograms: set.weightKg ?? 0)), \(reps) ponavljanja")
        case .bodyweight:
            values = String(localized: "\(reps) ponavljanja")
        case .weightedBodyweight:
            values = String(localized: "dodatno \(formatter.string(fromKilograms: set.extraWeightKg ?? 0)), \(reps) ponavljanja")
        case .assisted:
            values = String(localized: "pomoć \(formatter.string(fromKilograms: set.extraWeightKg ?? 0)), \(reps) ponavljanja")
        case .duration, .durationDistance:
            values = text
        }
        let title = number.map { String(localized: "Serija \($0)") } ?? String(localized: "Zagrijavanje")
        var parts = [title, values]
        if let rpe = set.rpe { parts.append("RPE \(NumberInput.format(rpe))") }
        return Text(verbatim: parts.joined(separator: ", "))
    }

    private var text: String {
        let formatter = WeightFormatter(unit: unit)
        switch inputType {
        case .weightReps:
            return "\(formatter.string(fromKilograms: set.weightKg ?? 0)) × \(set.reps ?? 0)"
        case .bodyweight:
            return "× \(set.reps ?? 0)"
        case .weightedBodyweight:
            return "+\(formatter.string(fromKilograms: set.extraWeightKg ?? 0)) × \(set.reps ?? 0)"
        case .assisted:
            return "−\(formatter.string(fromKilograms: set.extraWeightKg ?? 0)) × \(set.reps ?? 0)"
        case .duration:
            return DurationInput.format(set.durationSeconds ?? 0)
        case .durationDistance:
            let time = DurationInput.format(set.durationSeconds ?? 0)
            guard let meters = set.distanceMeters else { return time }
            return "\(time) · \(NumberInput.format(meters / 1000)) km"
        }
    }
}
